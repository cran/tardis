#' @useDynLib tardis, .registration = TRUE

handle_sentence_scores <- function(result, sigmoid_factor = 15, punctuation_factor = 1.15) {
  # dplyr data masking
  punct_exclamation <- punct_question <- sentence <- sentence_id <- sentence_punct <- sentence_score <- sentence_sum <- sentences <- sentiment_word <- text_id <- . <- NULL

  #step1 now takes roughly 90% of the time in this function. can it be sped up?
  # data.table was faster but won't work inside of the package with a clean
  # R CMD CHECK no matter what I try
  # https://stackoverflow.com/questions/50768717/failure-using-data-table-inside-package-function
  # Best option might be a custom cpp11 function to replace dplyr::summarise(),
  # but this seems like a lot of work for unclear reward.

  # get punctuation effect. one question mark has no effect. any exclamation point
  # does. get # of effective punctuation marks, scale up by punctuation factor.
  # we count punctuation using a cpp11 function for speed

  result$punct_count <- count_punct_cpp11(em = as.integer(result$punct_exclamation),
                                          qm = as.integer(result$punct_question))

  result$sentence_punct <- punctuation_factor ^ result$punct_count

  # because of a dplyr::summarise() quirk, we multiply each word by sentence_punct
  # inside the function call. if we do it outside (more aesthetically natural)
  # it does not reduce the number of rows, and returns one row per word
  step1 <- result %>%
    dplyr::group_by(text_id, sentence_id) %>%
    dplyr::summarise(sentence_score = sum(sentiment_word * sentence_punct, na.rm = TRUE)
                     , .groups = "drop_last"
    )

  if (!is.na(sigmoid_factor)){
    step1$sentence_score <- step1$sentence_score / sqrt((step1$sentence_score^2) + sigmoid_factor)
  }

  step1$sentence_sum <- step1$sentence_punct <- NULL

  return(step1)
}

handle_capitalizations <- function(result, allcaps_factor){
  result$allcaps <- 1 + (allcaps_factor * (result$word == toupper(result$word)))

  # make all words lowercase
  # again this is surprisingly slow
  result$word <- tolower(result$word)

  return(result)
}

handle_negations <- function(result, dict_negations_vec, negation_factor, use_negations){

  if (use_negations){
    result$negation <- dict_negations_vec[result$word]
    result$negation <- (dplyr::if_else(is.na(result$negation ), 0, result$negation))

    # get lagged negations
    result$negation1 <- lag1_indexed_vector(vector_index = result$sentence_id, vec_to_lag = result$negation)
    result$negation2 <- lag1_indexed_vector(vector_index = result$sentence_id, vec_to_lag = result$negation1)
    result$negation3 <- lag1_indexed_vector(vector_index = result$sentence_id, vec_to_lag = result$negation2)

    # here we apply the negation factor, doing the scaling and the -1 powers separately so we can have fractional powers
    # if there are ALL CAPS negations. not presently implemented
    # negations
    result$negations <- (negation_factor)^(result$negation1 + result$negation2 + result$negation3)*(-1)^floor(result$negation1 + result$negation2 + result$negation3)

    result$negation <- result$negation1 <- result$negation2 <- result$negation3 <- NULL
  } else {
    result$negations <- 1
  }
  return(result)
}

handle_modifiers <- function(result, dict_modifiers_vec, use_modifiers) {

  # if we're using modifiers, do the math.
  # otherwise, set the multiplicative factors to 1--i.e. no change.
  if (use_modifiers){
    result$modifier <- dict_modifiers_vec[result$word]
    result$modifier <- (dplyr::if_else(is.na(result$modifier ), 0, result$modifier))

    result$modifier_value <- result$modifier * result$allcaps

    # get laggd modifiers
    result$modifier1 <- lag1_indexed_vector(vector_index = result$sentence_id, vec_to_lag = result$modifier)
    result$modifier2 <- lag1_indexed_vector(vector_index = result$sentence_id, vec_to_lag = result$modifier1)
    result$modifier3 <- lag1_indexed_vector(vector_index = result$sentence_id, vec_to_lag = result$modifier2)

    result$modifiers <- 1 + (result$modifier1 + 0.95 * result$modifier2 + 0.9 * result$modifier3)

    result$modifier <- result$modifier1 <- result$modifier2 <- result$modifier3 <- NULL
  } else {

    result$modifiers <- 1

  }
  return(result)
}

# Function to split input texts into sentences and sort out emojis.
# This is presently the biggest bottleneck.
# Some of the main features have been done in c++ for speed, but the handling of
# ASCII emojis is especially slow because it uses regular expressions.
# In a future rewrite, I would focus here!
split_text_into_sentences_cpp11 <- function(sentences, emoji_regex_internal, dict_sentiments){
  # dplyr data masking
  sentence <- sentences_noemojis <- sentence <- emojis <- sentences_asciiemojis <- sentences_temp <- NULL
  #look behind for punctuation, look ahead for emojis
  # but only look for emojis that are present in the dictionary! huge time saver
  # 2022-09-25 regex string splitcontinues to be huge bottleneck, even with
  # extracting emojis separately and only splitting on "(?<=(\\.|!|\\?){1,5}\\s)"
  # 2022-09-26 this version does stringsplit using Rcpp to split after string of !,?,.
  #            which is ~25x faster than the regex
  # 2022-10-15 Adding ASCII emojis to the regex is very expensive and slow. My
  #            short-term solution is to have fewer emojis in the regex! Longer-
  #            term, could adjust the implementation to maybe use indexing...
  # 2022-10-18 Minor fix for ASCII emojis.

  emojis_in_dictionary <- dict_sentiments$token %>% stringr::str_subset(emoji_regex_internal)

  ascii_emoji_regex <- dict_sentiments$token %>%
    stringr::str_subset(":|;|=") %>%
    stringr::str_replace_all("(\\W)", "\\\\\\1") %>% # https://stackoverflow.com/questions/14836754/is-there-an-r-function-to-escape-a-string-for-regex-characters
    paste0(collapse = "|")

  ascii_emoji_regex <- paste0("(",ascii_emoji_regex,")")

  if (ascii_emoji_regex == "()") ascii_emoji_regex <- character(0)

  utf8_emoji_regex <- paste0(emojis_in_dictionary, collapse = "|")

  regex_pattern <- "(?<=(\\.|!|\\?){1,5}\\s)"

  # need an id for each text, then one for each sentence.
  sentences$text_id <- 1:nrow(sentences)

  # preprocessing for ascii emojis, replacing them with ". :) ." to break sentences.
  # Then we need to remove any spurious periods below.
  # this is much more natural with UTF-8 emojis! this is also a performance bottleneck.
  if (length(ascii_emoji_regex) > 0) {
    step0 <- sentences %>%
      dplyr::mutate(sentences_asciiemojis = gsub(x = sentences, pattern = ascii_emoji_regex, replacement = ". \\1 ."))
  } else {
    step0 <- sentences
    step0$sentences_asciiemojis <- step0$sentences
  }

  # only extract emojis if there are any in the dictionary. otherwise create a
  # tibble with empty column for emojis
  if (utf8_emoji_regex != ""){
    step1 <- step0 %>%
      dplyr::mutate(emojis = stringr::str_extract_all(sentences_asciiemojis, utf8_emoji_regex))

    step2 <- step1 %>%
      dplyr::mutate(sentences_noemojis = stringr::str_replace_all(sentences_asciiemojis, utf8_emoji_regex, "."))

  } else {
    step2 <- step0 %>%
      dplyr::mutate(sentences_noemojis = sentences_asciiemojis, emojis = list(rep(character(length = 0L), times = nrow(sentences))))
  }

  step3cpp11 <- step2 %>%
    #dplyr::mutate(sentence = stringi::stri_split_regex(str = sentences_noemojis, pattern = regex_pattern, simplify = FALSE, omit_empty = TRUE))
    dplyr::mutate(sentence = purrr::map(sentences_noemojis, split_string_after_punctuation_cpp11)) #split_string_after_punctuation))

  step4 <- step3cpp11 %>%
    dplyr::mutate(sentences_temp = purrr::map2(sentence, emojis, function(x,y) {
      c(x, y)
    }))

  step5 <- step4 %>%
    dplyr::select(-emojis, -sentences_noemojis, -sentence) %>%
    tidyr::unnest(sentences_temp) %>%
    dplyr::rename(sentence = sentences_temp) %>%
    dplyr::mutate(sentence = stringr::str_remove(sentence, "^\\s+"))

  result <- step5 %>%
    dplyr::filter(sentence != ".") # remove any singletons from ascii emojis

  # assign unique sentence ids
  result$sentence_id <- 1:nrow(result)

  #print(result)
  return(result)
}



# custom function to lag a vector based on the values in an index vector
# essentially a custom version of dplyr::group() %>% dplyr::lag() but MUCH faster.
# vector_index is a vector of monotonically increasing integers indicating groups
# vec_to_lag is the vector to be lagged
# NOTE this seems 50x faster than the dplyr functions, which were the bottleneck
# this could be easily converted to Rcpp if necessary / worth it
lag1_indexed_vector <- function(vector_index, vec_to_lag) {

  vec_length <- length(vector_index)
  vec_lagged1 <- rep(0, vec_length)
  last_id <- 0

  for (i in 1:vec_length){
    #message(i)
    # new sentence id
    if ((vector_index[[i]] != last_id)  ) {
      last_id <- vector_index[[i]]
      vec_lagged1[[i]] <- 0
    } else {
      vec_lagged1[[i]] <- vec_to_lag[[i-1]]
    }

  }

  return (vec_lagged1)
}
