# TODO: Only install WCBench, link with ODL Docker image

# Base the image on Debian 7
# Picked Debian because it's small (85MB)
# https://registry.hub.docker.com/_/debian/
FROM fedora:20
MAINTAINER Daniel Farrell <dfarrell@redhat.com>

# Install required software
# Doing here, instead of with `-ci`, to allow better caching
# TODO: Don't install ODL deps here, link with ODL Docker image
RUN yum install -y java-1.7.0-openjdk unzip wget sshpass net-snmp-devel libpcap-devel autoconf make automake libtool libconfig-devel git

# Allow sudo commands in wcbench.sh to work
RUN sed -i '/requiretty/s/^/#/' /etc/sudoers

# TODO: Do CBench install manually so it can be cached

# Drop source in /opt dir
# Do the ADD as late as possible, as it invalidates cache
ADD . /opt/wcbench

WORKDIR /opt/wcbench
# TODO: Don't install ODL here, link with ODL Docker image
RUN ./wcbench.sh -ci
