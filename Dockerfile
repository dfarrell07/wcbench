# TODO: Link with ODL Docker image

# Base the image on Debian 7
# Picked Debian because it's small (85MB)
# https://registry.hub.docker.com/_/debian/
FROM fedora:20
MAINTAINER Daniel Farrell <dfarrell@redhat.com>

# Install required software
# Doing here, instead of with `-ci`, to allow better caching
RUN yum install -y sshpass net-snmp-devel libpcap-devel autoconf make automake libtool libconfig-devel git

# Allow sudo commands in wcbench.sh to work
RUN sed -i '/requiretty/s/^/#/' /etc/sudoers

# Do CBench install manually so it can be cached
RUN git clone https://github.com/andi-bigswitch/oflops.git /root/oflops
RUN git clone git://gitosis.stanford.edu/openflow.git /root/openflow
RUN cd /root/oflops && ./boot.sh && ./configure --with-openflow-src-dir=/root/openflow && make && sudo make install

# Drop source in /opt dir
# Do the ADD as late as possible, as it invalidates cache
ADD . /opt/wcbench

WORKDIR /opt/wcbench
