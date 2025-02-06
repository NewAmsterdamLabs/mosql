FROM ruby:3.3-alpine

ARG PACKAGES='alpine-sdk git libpq-dev'
COPY Gemfile Gemfile.lock ./
RUN apk update \
    && apk add --update --no-cache ${PACKAGES}

# Set the working directory
WORKDIR /app

COPY . /app

RUN bundle install

