FROM ruby:3.0-alpine3.16

RUN apk update
RUN apk add --no-cache build-base gcc cmake git ruby-jekyll