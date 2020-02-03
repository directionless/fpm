# Are we running against the minimal container, or the everything
# container? Minimal is mostlty the compiled package tools. Everything
# pulls in scripting langauges.
ARG BASE_ENV=minimal

# Are we running tests, or a release? Tests build and run against the
# CWD, where release will use the downloaded gem.
ARG TARGET=test

# Container to throw an error if called with a bare `docker build .`
FROM ubuntu:18.04 as error
RUN echo "\n\n\nHey! Use buildkit. See the Makefile or docs\n\n\n"
RUN false

# Base container is used for various release and test things
FROM ubuntu:18.04 as minimal-base

# Runtime deps. Build deps go in the build or test containers
RUN apt-get update \
	&& apt-get -y dist-upgrade \
	&& apt-get install --no-install-recommends -y \
	ruby rubygems rubygems-integration \
	bsdtar \
	cpio \
	debsigs \
	pacman \
	rpm  \
	squashfs-tools \
	xz-utils \
	zip \
	&& rm -rf /var/lib/apt/lists/* \
	&& apt-get clean

# everything container includes all the scripting languages. These
# greatly embiggen the underlying docker container, so they're
# conditionalized.
FROM minimal-base AS everything-base
RUN apt-get update \
	&& apt-get install --no-install-recommends -y \
	cpanminus \
	npm \
	perl \
	python3-pip \
	&& pip3 --no-cache-dir install setuptools \
	&& pip3 --no-cache-dir install wheel \
	&& pip3 --no-cache-dir install virtualenv virtualenv-tools3 \
	&& update-alternatives --install /usr/bin/python python /usr/bin/python3 10 \
	&& rm -rf /var/lib/apt/lists/*


# Run tests against the current working directory. This is a bit
# orthogonal to the container release process, but it has a lot of
# same dependancies, so we reuse it. This uses COPY to prep the gem
# files, but expects you to volume mount into /src
FROM ${BASE_ENV}-base AS test
WORKDIR /src
RUN apt-get update \
	&& apt-get install --no-install-recommends -y \
	gcc make ruby-dev libc-dev lintian git
# installing ffi here is a bit of an optimization for how COPY and layer reuse works
RUN gem install --no-ri --no-rdoc bundler ffi
RUN mkdir /origsrc
COPY . /origsrc
RUN cd /origsrc && bundle install
ENTRYPOINT ["rspec"]

# build a container from a released gem. install build deps here, so
# we can omit them from the final release package
#ARG BASE=everything
FROM ${BASE_ENV}-base AS build
RUN apt-get update
RUN apt-get install --no-install-recommends -y \
	gcc make ruby-dev libc-dev
ENV GEM_PATH /fpm
ENV PATH "/fpm/bin:${PATH}"
RUN gem install --no-ri --no-rdoc --install-dir=/fpm fpm

FROM build as release
COPY --from=build /fpm /fpm
ENV GEM_PATH /fpm
ENV PATH "/fpm/bin:${PATH}"
ENTRYPOINT ["/fpm/bin/fpm"]

# This target is to help docker buildkit in resolving things.
FROM ${TARGET} as final
