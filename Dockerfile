# syntax=docker/dockerfile:1

ARG RUBY_VERSION=3.4.5
FROM ruby:$RUBY_VERSION-slim AS base

# Set Rails app working directory
WORKDIR /rails

# Install base OS packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libjemalloc2 libvips postgresql-client build-essential git libpq-dev libyaml-dev pkg-config nodejs yarn && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

# Set environment variables
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

# --------------------
# Build Stage
# --------------------
FROM base AS build

# Copy Gemfile and install gems first for caching
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy the rest of the app code
COPY . .

# Make bin scripts executable
RUN chmod +x bin/* && \
    sed -i "s/\r$//g" bin/* && \
    sed -i 's/ruby\.exe$/ruby/' bin/*

# Precompile assets without requiring master key
RUN SECRET_KEY_BASE_DUMMY=1 RAILS_ENV=production ./bin/rails assets:precompile

# --------------------
# Final Stage
# --------------------
FROM base

# Copy built gems and app code from build stage
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Set up a non-root user
RUN groupadd --system --gid 1000 rails && \
    useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash rails && \
    chown -R rails:rails /rails /usr/local/bundle db log storage tmp
USER rails

# Entrypoint & server
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
