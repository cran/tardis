
testthat::test_that("Emojis are recognized",{
  testthat::expect_gt(tardis("❤️")$score , 0)
  testthat::expect_lt(tardis("😭")$score, 0)
  testthat::expect_gt(tardis(":)")$score , 0)
  testthat::expect_lt(tardis(":(")$score , 0)
})

testthat::test_that("Leading and trailing punctuation isn't considered",{
  testthat::expect_equal(tardis("(happy)")$score , tardis("happy")$score)
  testthat::expect_equal(tardis("'sad' is how i feel")$score , tardis("sad is how i feel")$score)
})

testthat::test_that("Capitalization amplifies sentiment",{
  testthat::expect_gt(tardis("HAPPY")$score , tardis("happy")$score)
  testthat::expect_lt(tardis("SAD")$score , tardis("sad")$score)
})

testthat::test_that("Punctuation amplifies sentiment up to 3 points, and not for one question mark",{
  testthat::expect_gt(tardis("happy!")$score , tardis("happy")$score)
  testthat::expect_gt(tardis("happy!!")$score , tardis("happy!")$score)
  testthat::expect_gt(tardis("happy!?!")$score , tardis("happy!!")$score)
  testthat::expect_equal(tardis("happy!?!?!!")$score , tardis("happy!?!")$score)
  testthat::expect_equal(tardis("happy?")$score , tardis("happy")$score)
  testthat::expect_lt(tardis("sad!")$score , tardis("sad")$score)
})


testthat::test_that("Punctuation can be disabled",{
  testthat::expect_equal(tardis("happy!", use_punctuation = FALSE)$score , tardis("happy")$score)
  testthat::expect_equal(tardis("sad!!?!?!", use_punctuation = FALSE)$score , tardis("sad")$score)
})

testthat::test_that("Punctuation and capitalization together amplifies sentiment",{
  testthat::expect_gt(tardis("HAPPY!")$score , tardis("happy!")$score)
  testthat::expect_lt(tardis("SAD!")$score , tardis("sad!")$score)
})

testthat::test_that("Cpp11 function to split sentences works properly", {
  temp_dict_sentiments <- dplyr::tibble(token = "happy")
  temp_dict_emojis <- emoji_regex_internal#""
  test1 <- dplyr::tibble(sentences = "hi! you!")
  test2 <- dplyr::tibble(sentences = "HI!!!! you??!!! wow")
  test3 <- dplyr::tibble(sentences = "hi.. there...?? you!!!!!")
  testthat::expect_equal(split_text_into_sentences_cpp11(test1 , temp_dict_emojis, temp_dict_sentiments )$sentence,
                         c("hi!", "you!"))
  testthat::expect_equal(split_text_into_sentences_cpp11(test2 , temp_dict_emojis, temp_dict_sentiments )$sentence,
                         c("HI!!!!", "you??!!!","wow"))
  testthat::expect_equal(split_text_into_sentences_cpp11(test3 , temp_dict_emojis, temp_dict_sentiments )$sentence,
                         c("hi..", "there...??", "you!!!!!"))
})


testthat::test_that("Cpp11 function to take pairwise nonzero value from two vectors", {
  testthat::expect_equal(get_nonzero_value_cpp11(c(1,0,1),
                                                 c(0,2,2)),
                         c(1,2,1))
})


testthat::test_that("Custom dictionaries with no emojis work properly", {
  custom_dict <- dplyr::tribble(~token, ~score,
                                "happy", 5,
                                "sad", -5)
  testthat::expect_gt(tardis("happy", dict_sentiments = custom_dict)$score, 0)
  testthat::expect_equal(tardis("jumpin' jehosephat")$score, 0)
  testthat::expect_lt(tardis("sad", dict_sentiments = custom_dict)$score, 0)

})

testthat::test_that("Custom dictionaries that are ONLY emojis work properly", {
  custom_dict <- dplyr::tribble(~token, ~score,
                                "❤️", 5,
                                "😭", -5)
  testthat::expect_gt(tardis("❤️", dict_sentiments = custom_dict)$score, 0)
  testthat::expect_equal(tardis("jumpin' anacondas")$score, 0)
  testthat::expect_lt(tardis("😭", dict_sentiments = custom_dict)$score, 0)

})

testthat::test_that("Custom dictionaries with text and emojis work properly", {
  custom_dict <- dplyr::tribble(~token, ~score,
                                "❤️", 5,
                                "sadness", -5,
                                ":D", 5)
  testthat::expect_gt(tardis("❤️", dict_sentiments = custom_dict)$score, 0)
  testthat::expect_gt(tardis("time for lunch :D", dict_sentiments = custom_dict)$score, 0)
  testthat::expect_equal(tardis("jumpin' jehosephat")$score, 0)
  testthat::expect_lt(tardis("sadness", dict_sentiments = custom_dict)$score, 0)

})

testthat::test_that("Custom dictionaries with multi-word tokens work properly",{
  custom_dict <- dict_tardis_sentiment %>%
    dplyr::add_row(token = "supreme court", score = 0) %>%
    dplyr::add_row(token = "happy sad", score = 0) %>%
    dplyr::add_row(token = "oh dear", score = -3)


  # if multi-word tokens  have sentiment-bearing sub-components, the subcomponents still work fine
  testthat::expect_gt(tardis("supreme", dict_sentiments = custom_dict)$score, 0)
  testthat::expect_equal(tardis("supreme court", dict_sentiments = custom_dict)$score, 0)

  testthat::expect_gt(tardis("happy", dict_sentiments = custom_dict)$score, 0)
  testthat::expect_equal(tardis("happy sad", dict_sentiments = custom_dict)$score, 0)
  testthat::expect_lt(tardis("sad", dict_sentiments = custom_dict)$score, 0)

  # multi-word tokens work when next to punctuation
  testthat::expect_lt(tardis("oh dear", dict_sentiments = custom_dict)$score, 0)
  testthat::expect_lt(tardis("oh dear!", dict_sentiments = custom_dict)$score,
                      tardis("oh dear", dict_sentiments = custom_dict)$score)
  testthat::expect_lt(tardis("oh dear!", dict_sentiments = custom_dict)$score, 0)
  })


testthat::test_that("Modifiers work as expected", {
  # modifiers amplify direction
  testthat::expect_gt(tardis("very happy")$score, tardis("happy")$score)
  testthat::expect_lt(tardis("very sad")$score, tardis("sad")$score)

  # modifiers work up to 3 steps back but no more
  testthat::expect_gt(tardis("very very happy")$score, tardis("very happy")$score)
  testthat::expect_gt(tardis("very very very happy")$score, tardis("very very happy")$score)
  testthat::expect_equal(tardis("very very very very happy")$score, tardis("very very very happy")$score)

  # multi-word modifiers work okay
  custom_modifiers <- dplyr::tibble(token = c("very", "gosh darn"), score = 0.25)
  testthat::expect_gt(tardis("very happy", dict_modifiers = custom_modifiers)$score, tardis("happy", dict_modifiers = custom_modifiers)$score)
  testthat::expect_gt(tardis("gosh darn happy", dict_modifiers = custom_modifiers)$score, tardis("happy", dict_modifiers = custom_modifiers)$score)
  testthat::expect_lt(tardis("gosh darn sad", dict_modifiers = custom_modifiers)$score, tardis("sad", dict_modifiers = custom_modifiers)$score)
  testthat::expect_equal(tardis("gosh darn happy", dict_modifiers = custom_modifiers)$score, tardis("very happy", dict_modifiers = custom_modifiers)$score)

  # modifiers can be disabled
  testthat::expect_equal(tardis("very happy", dict_modifiers = "none")$score, tardis("happy")$score)
  testthat::expect_equal(tardis("very sad", dict_modifiers = "none")$score, tardis("sad")$score)
})

testthat::test_that("Negations work as expected",{

  testthat::test_that("Negations flip direction",{
  testthat::expect_lt(tardis("not happy")$score, tardis("happy")$score)
  testthat::expect_gt(tardis("not sad")$score, tardis("sad")$score)

  })

  # negations damp effect sizes
  testthat::expect_lt(abs(tardis("not happy")$score), abs(tardis("happy")$score))
  testthat::expect_lt(abs(tardis("not sad")$score), abs(tardis("sad")$score))

  # negations work up to 3 steps back but no more
  testthat::expect_lt(abs(tardis("not not happy")$score), abs(tardis("not happy")$score))
  testthat::expect_lt(abs(tardis("not not not happy")$score), abs(tardis("not not happy")$score))
  testthat::expect_equal(tardis("not not not not happy")$score, tardis("not not not happy")$score)

  # multi-word negations work okay
  custom_negations <- dplyr::tibble(token = c("not", "ain't no", "isn’t"))
  testthat::expect_equal(tardis("not good", dict_negations = custom_negations)$score, tardis("isn’t good", dict_negations = custom_negations)$score)
  testthat::expect_equal(tardis("not good", dict_negations = custom_negations)$score, tardis("aint no good", dict_negations = custom_negations)$score)
  testthat::expect_equal(tardis("not good", dict_negations = custom_negations)$score, tardis("ain't no good", dict_negations = custom_negations)$score)
  testthat::expect_lt(tardis("ain't no good", dict_negations = custom_negations)$score, tardis("good", dict_negations = custom_negations)$score)
  testthat::expect_gt(tardis("ain't no bad", dict_negations = custom_negations)$score, tardis("bad", dict_negations = custom_negations)$score)

  # negations can be disabled
  testthat::expect_equal(tardis("not happy", dict_negations = "none")$score, tardis("happy")$score)
  testthat::expect_equal(tardis("not sad", dict_negations = "none")$score, tardis("sad")$score)

})


testthat::test_that("Parameter simple_count works as expected with tbl_df input", {
  testthat::expect_equal(tardis(stringr::sentences,
                                sigmoid_factor = NA, allcaps_factor = 1, dict_modifiers = "none", dict_negations = "none", use_punctuation = FALSE, summary_function = "sum"),
                         suppressWarnings(tardis(stringr::sentences, simple_count = TRUE)))
})


testthat::test_that("Multi-dictionary wrapper functions works", {
  dictionaries <- dplyr::tibble(dictionary = c("good", "good", "bad", "bad"),
                                token = c("good", "great", "bad", "awful"),
                                score = c(1, 2, 1, 2))

  input_texts <- dplyr::tibble(body = c("this is good.",
                                        "this is great.",
                                        "this is bad.",
                                        "this is not bad.",
                                        "this is awful.",
                                        "this is awful!"))

  result <- tardis::tardis_multidict(input_text = input_texts,
                                     text_column = "body",
                                     dictionaries = dictionaries) %>%
    dplyr::select(body, score_good, score_bad)

  # we get the basic output form we expect
  testthat::expect_s3_class(result, "tbl_df")
  testthat::expect_equal(nrow(result), nrow(input_texts))

  # good works properly
  testthat::expect_gt(result[2,]$score_good, result[1,]$score_good)
  testthat::expect_equal(result[2,]$score_bad, 0)

  # bad works properly
  testthat::expect_gt(result[5,]$score_bad, result[4,]$score_bad)

  # punctuation works
  testthat::expect_gt(result[6,]$score_bad, result[5,]$score_bad)

  # negation works
  testthat::expect_lt(result[4,]$score_bad, 0)

  # vector input works
  result_vec <- tardis::tardis_multidict(c("good dog", "bad dog"), dictionaries = dictionaries)
  testthat::expect_equal(result_vec[1,]$score_good, 0.25)
  testthat::expect_equal(result_vec[2,]$score_bad, 0.25)
})


testthat::test_that("cpp function count_punct_cpp11 works", {
  testthat::expect_equal(count_punct_cpp11(em = as.integer(c(0,1,1,5)), qm = as.integer(c(1, 0, 1, 5))),
                         c(0,1,2,3))
})
