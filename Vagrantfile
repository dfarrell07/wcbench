VAGRANTFILE_API_VERSION = "2"

# The WCBench README describes how to use Vagrant for WCBench work
# See: https://github.com/dfarrell07/wcbench#user-content-detailed-walkthrough-vagrant

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
    # Build Vagrant box based on Fedora 20
    config.vm.box = "chef/fedora-20"

    # Configure VM RAM and CPU
    config.vm.provider "virtualbox" do |v|
      v.memory = 2048
      v.cpus = 4
    end

    # This allows sudo commands in wcbench.sh to work
    config.ssh.pty = true

    # Configuration specific to VM with OpenDaylight
    config.vm.define "odl" do |odl|
        # Install Puppet
        odl.vm.provision "shell", inline: "yum install -y puppet"

        # Install OpenDaylight using its Puppet module
        odl.vm.provision "puppet" do |puppet|
            # These are all default settings, just stating explicitly for clarity
            puppet.module_path = ["modules"]
            puppet.manifest_file = "default.pp"
            puppet.manifests_path = "manifests"
        end
    end

    # Configuration specific to VM with WCBench
    config.vm.define "wcbench" do |wcbench|
        # Unexpectedly, /usr/local/bin isn't in the default path
        # The cbench and oflops binary install there, need to add it
        wcbench.vm.provision "shell", inline: "echo export PATH=$PATH:/usr/local/bin >> /home/vagrant/.bashrc"
        wcbench.vm.provision "shell", inline: "echo export PATH=$PATH:/usr/local/bin >> /root/.bashrc"

        # Drop code in /home/vagrant/wcbench, not /vagrant
        wcbench.vm.synced_folder ".", "/vagrant", disabled: true
        wcbench.vm.synced_folder ".", "/home/vagrant/wcbench"

        # Install CBench with verbose output
        wcbench.vm.provision "shell", inline: 'su -c "/home/vagrant/wcbench/wcbench.sh -vc" vagrant'
    end
end
