VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
    # Build Vagrant box based on Fedora 20
    config.vm.box = "chef/fedora-20"

    # This allows sudo commands to work
    config.ssh.pty = true

    # Unexpectedly, /usr/local/bin isn't in the default path
    # The cbench and oflops binary install there, need to add it
    config.vm.provision "shell", inline: "echo export PATH=$PATH:/usr/local/bin >> /home/vagrant/.bashrc"
    config.vm.provision "shell", inline: "echo export PATH=$PATH:/usr/local/bin >> /root/.bashrc"

    # Drop code in /home/vagrant/wcbench, not /vagrant
    config.vm.synced_folder ".", "/vagrant", disabled: true
    config.vm.synced_folder ".", "/home/vagrant/wcbench"

    config.vm.provision "shell", inline: 'su -c "/home/vagrant/wcbench/wcbench.sh -vci" vagrant'
end
