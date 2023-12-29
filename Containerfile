FROM steamcmd:latest

MAINTAINER envyniv <envyn67@gmail.com>

ARG 

RUN echo ""\
    ./steamcmd.sh +force_install_dir /home/steam/squad-dedicated +login anonymous +app_update 403240 +quit
