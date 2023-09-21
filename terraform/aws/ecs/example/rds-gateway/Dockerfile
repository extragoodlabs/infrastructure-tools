# bump version 0.61
FROM ghcr.io/extragoodlabs/jumpwire:latest

ARG db_name
ARG db_username
ARG db_password
ARG db_hostname

# Create app directory
WORKDIR /etc/jumpwire

# Create config with RDS connection string
COPY jumpwire.yaml ./
# COPY GoogleIDPMetadata.xml ./idp.xml
# COPY test-db.hook.jumpwire.cloud+1.pem ./cert.pem
# COPY test-db.hook.jumpwire.cloud+1-key.pem ./key.pem

RUN sed -i "s|DB_NAME|$db_name|" ./jumpwire.yaml
RUN sed -i "s|DB_USERNAME|$db_username|" ./jumpwire.yaml
RUN sed -i "s|DB_PASSWORD|$db_password|" ./jumpwire.yaml
RUN sed -i "s|DB_HOSTNAME|$db_hostname|" ./jumpwire.yaml

ENV JUMPWIRE_CONFIG_PATH=/etc/jumpwire
# ENV JUMPWIRE_SSO_METADATA_PATH=/etc/jumpwire/idp.xml
# ENV JUMPWIRE_SSO_IDP=google
# ENV JUMPWIRE_SSO_SIGNED_ENVELOPES=false
# ENV JUMPWIRE_TLS_CERT=/etc/jumpwire/cert.pem
# ENV JUMPWIRE_TLS_KEY=/etc/jumpwire/key.pem
