# --- Base image with specific Java version ---
ARG JAVA_VERSION=25
FROM eclipse-temurin:${JAVA_VERSION}-jre-alpine

# --- Build arguments and environment variables ---
ARG PORT=25565
ARG GREGTECH_VERSION=2.8.1
ARG GREGTECH_JAVA_VERSION=17-25
ARG USER="minecraft"

ENV GREGTECH_VERSION=$GREGTECH_VERSION \
      GREGTECH_JAVA_VERSION=$GREGTECH_JAVA_VERSION \
      USER=${USER} \
      HOME_DIR=/home/${USER}

# --- Labels for metadata ---
LABEL image.title="GregTech - New Horizons" \
      image.description="Ein Docker-Image für einen Minecraft Greg Tech - New Horizons Server" \
      image.version="1.3" \
      image.source="https://github.com/Sling2009/gregTech.git" \
      image.licenses="MIT" \
      image.authors="Axel Fischer <axel.fischer@fam-fis.de>" \
      minecraft.gregtech.version=${GREGTECH_VERSION} \
      minecraft.gregtech.java.version=${GREGTECH_JAVA_VERSION} \
      minecraft.java.version=${JAVA_VERSION}

# --- Install required packages ---
# hadolint ignore=DL3018
RUN apk update && apk add --no-cache unzip curl bash shadow jq

# --- Create non-root user ---
RUN useradd -m -u 99 -g 100 -d ${HOME_DIR} -s /bin/bash ${USER}

# Set working directory and copy launch script ---
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh && \
      ln -s /entrypoint.sh /usr/local/bin/entrypoint

# --- Set permissions and switch to non-root user ---
USER ${USER}

VOLUME ${HOME_DIR}
WORKDIR ${HOME_DIR}

# --- Expose server port ---
EXPOSE ${PORT}

# --- Health check: TCP-Verbindung auf den Minecraft-Port ---
HEALTHCHECK --interval=60s --timeout=10s --start-period=180s --retries=3 \
  CMD bash -c '(echo >/dev/tcp/localhost/25565) 2>/dev/null && exit 0 || exit 1'

# --- Entry point ---
ENTRYPOINT ["entrypoint"]

