#!/usr/bin/env bats

load helpers/fixtures

setup() { ct_load_lib; }

@test "slugify lowercases and hyphenates" {
  run ct_slugify "ABC-700 Fix the thing"
  [ "$output" = "abc-700-fix-the-thing" ]
}

@test "slugify collapses runs of punctuation" {
  run ct_slugify "Fix: the thing -- again!!"
  [ "$output" = "fix-the-thing-again" ]
}

@test "slugify trims leading and trailing hyphens" {
  run ct_slugify "  --hello--  "
  [ "$output" = "hello" ]
}

@test "slugify preserves existing valid slugs" {
  run ct_slugify "abc-700-autofix"
  [ "$output" = "abc-700-autofix" ]
}

@test "slugify returns empty for punctuation-only input" {
  run ct_slugify "!!!"
  [ "$output" = "" ]
}
