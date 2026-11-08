# The tests on Linux (tests/linux/run.sh builds and runs it, docs/tests.md):
# Debian with GNU Emacs 31.1 built from GNU's release as scripts/emacs.sh
# builds it (GTK3, tree-sitter, xwidgets: WebKitGTK; --build-arg
# EMACS_CONFIGURE_EXTRA= leaves xwidgets out, as most distributions do), and
# the programs the config and the tests run.
FROM debian:trixie

ARG EMACS_VERSION=31.1
ARG EMACS_CONFIGURE_EXTRA="--with-xwidgets"
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

# Build dependencies (kept: the runtime libraries come with them).
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential pkg-config curl ca-certificates xz-utils \
      libgtk-3-dev libwebkit2gtk-4.1-dev libtree-sitter-dev \
      libxpm-dev libpng-dev libjpeg-dev libgif-dev libtiff-dev libwebp-dev \
      librsvg2-dev libgnutls28-dev libxml2-dev libncurses-dev libharfbuzz-dev \
      libcairo2-dev libsqlite3-dev libgmp-dev libacl1-dev libdbus-1-dev \
      liblcms2-dev libselinux1-dev libsystemd-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir /src && cd /src \
    && curl -fsSL https://ftpmirror.gnu.org/emacs/emacs-${EMACS_VERSION}.tar.xz -o emacs.tar.xz \
    && tar xf emacs.tar.xz && cd emacs-${EMACS_VERSION} \
    && ./configure --prefix=/usr/local \
         --with-x-toolkit=gtk3 ${EMACS_CONFIGURE_EXTRA} --with-tree-sitter \
         --with-xpm --with-png --with-jpeg --with-gif --with-tiff --with-webp \
         --with-rsvg --with-gnutls --with-xml2 --with-cairo --with-harfbuzz \
         --with-sqlite3 --with-modules --with-dbus \
         --with-native-compilation=no --without-compress-install \
    && make -j"$(nproc)" && make install \
    && cd / && rm -rf /src

# What the tests (and the config they load) call.
RUN apt-get update && apt-get install -y --no-install-recommends \
      git python3 pandoc imagemagick ripgrep git-delta \
      xvfb xauth dbus dbus-x11 util-linux procps \
      fonts-dejavu fonts-noto-color-emoji \
    && rm -rf /var/lib/apt/lists/*

# The config's fonts, as on the Mac: JetBrains Mono, Nerd Fonts' symbols
# (nerd-icons).
RUN apt-get update && apt-get install -y --no-install-recommends fonts-jetbrains-mono unzip \
    && mkdir -p /usr/local/share/fonts/nerd \
    && curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip -o /tmp/n.zip \
    && unzip -o /tmp/n.zip -d /usr/local/share/fonts/nerd && rm /tmp/n.zip && fc-cache -f \
    && rm -rf /var/lib/apt/lists/*

ENV HOME=/root
WORKDIR /root/.config/doom
