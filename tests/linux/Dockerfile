# The tests on Linux (tests/linux/run.sh builds and runs it; GitHub Actions
# too: docs/tests.md). Debian, set up as a user sets up theirs: Emacs by
# scripts/emacs.sh (GNU's release built from source, with xwidgets: WebKitGTK;
# XWIDGETS=no leaves them out, as most distributions do), then what init.el
# and the config need by scripts/tools.sh; and what the tests need on top.
# Doom isn't in it: the tests mount Doom's folder (synced for this Emacs).
#
# Built from the repository's root (`docker build -f tests/linux/Dockerfile
# .'): it copies the scripts and init.el (Dockerfile.dockerignore: nothing
# else). Each step's layer is cached until what it copies changes: Emacs's
# build, the longest, until scripts/emacs.sh (or os.sh, ui.sh) does.
FROM debian:trixie

ARG EMACS_VERSION=31.1
ARG XWIDGETS=yes
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 HOME=/root \
    PATH=/root/.local/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# What the scripts need first (README: git, curl; root needs no sudo).
RUN apt-get update && apt-get install -y --no-install-recommends git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Emacs, as scripts/emacs.sh installs it (Doom left out: NO_DOOM).
COPY scripts/ui.sh scripts/os.sh scripts/emacs.sh /setup/scripts/
RUN EMACS_VERSION=$EMACS_VERSION XWIDGETS=$XWIDGETS NO_DOOM=1 /setup/scripts/emacs.sh \
    && rm -rf /var/lib/apt/lists/*

# What init.el and the config need, as scripts/tools.sh installs it.
COPY scripts/tools.sh /setup/scripts/
COPY init.el /setup/
RUN DOOM_INIT=/setup/init.el /setup/scripts/tools.sh && rm -rf /var/lib/apt/lists/*

# The tests' own: an X server and D-Bus for the GUI Emacs of the end-to-end
# tests, fonts for what the config's leave out, and Nerd Fonts' symbols (on
# Linux tools.sh leaves them to M-x nerd-icons-install-fonts; the merge's rows
# line up in the config's fonts).
RUN apt-get update && apt-get install -y --no-install-recommends \
      xvfb xauth dbus dbus-x11 procps unzip fonts-dejavu fonts-noto-color-emoji \
    && mkdir -p /usr/local/share/fonts/nerd \
    && curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip -o /tmp/n.zip \
    && unzip -o /tmp/n.zip -d /usr/local/share/fonts/nerd && rm /tmp/n.zip && fc-cache -f \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root/.config/doom
