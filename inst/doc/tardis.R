## ---- include = FALSE---------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>"
)

## ----setup--------------------------------------------------------------------
library(dplyr, warn.conflicts = FALSE)
library(tardis)

## -----------------------------------------------------------------------------
library(tardis)
library(dplyr)
library(knitr)

text <- c("This is not good.", 
          "This is not right.", 
          "My feet stick out of bed all night.", 
          "And when I pull them in, oh dear!", 
          "My feet stick out of bed up here!")

tardis::tardis(text) %>%
  dplyr::select(sentences, score) %>%
  knitr::kable()

## -----------------------------------------------------------------------------
custom_dictionary <- dplyr::add_row(tardis::dict_tardis_sentiment,
                                    token = "oh dear", score = -1)

tardis::tardis(text, dict_sentiments = custom_dictionary) %>%
  dplyr::select(sentences, score) %>%
  knitr::kable()


## -----------------------------------------------------------------------------
text <- c("I guess so, that might be fine. I don't know.",
          "Wow, you're really smart. MORON!",
          "It's the worst idea I've ever heard 😘" )

tardis::tardis(text) %>%
  knitr::kable()

## ----warn=FALSE---------------------------------------------------------------
dict_cats <- dplyr::tibble(token = c("cat", "cats"), score = c(1, 1))

text <- c("I love cats.", "Not a cat?!?!", "CATS CATS CATS!!!")

tardis::tardis(text, dict_sentiments = dict_cats, simple_count = TRUE) %>%
  dplyr::select(sentences, score) %>%
  knitr::kable()

