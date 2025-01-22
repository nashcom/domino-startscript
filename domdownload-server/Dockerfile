############################################################################
# Copyright Nash!Com, Daniel Nashed 2024 - APACHE 2.0 see LICENSE
############################################################################

FROM alpine:latest

USER root
COPY install_dir/* / 
RUN /install.sh

# Expose Ports HTTPS
EXPOSE 8888 

ENTRYPOINT ["/entrypoint.sh"]

USER 1000
