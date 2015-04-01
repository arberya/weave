#!/bin/bash

set -ex

# Poor mans vagrant; cannot run vagrant on travis!
KEY_FILE=/tmp/gce_private_key.json
SSH_KEY_FILE=$HOME/.ssh/gce_ssh_key
PROJECT=positive-cocoa-90213
IMAGE=ubuntu-14-04
ZONE=us-central1-a
NUM_HOSTS=2

# Setup authentication
gcloud auth activate-service-account --key-file $KEY_FILE
gcloud config set project $PROJECT

# Delete all vms in this account
function destroy {
	names="$(gcloud compute instances list --format=yaml | grep "^name\:" | cut -d: -f2 | xargs echo)"
	if [ -n "$names" ]; then
		gcloud compute instances delete --zone $ZONE -q $names
	fi
}

function ExternalIPFor {
	ipadd="$(gcloud compute instances list $1 --format=yaml | grep "^    natIP\:" | cut -d: -f2)"
	echo "$ipadd"
}

function InternalIPFor {
	ipadd="$(gcloud compute instances list $1 --format=yaml | grep "^  networkIP\:" | cut -d: -f2)"
	echo "$ipadd"
}

# Create new set of VMS
function setup {
	destroy

	# Create and setup some VMs
	for i in $(seq 1 $NUM_HOSTS); do
		name="host$i"
		gcloud compute instances create $name --image $IMAGE --zone $ZONE
	done

	gcloud compute config-ssh --ssh-key-file $SSH_KEY_FILE

	hosts=
	for i in $(seq 1 $NUM_HOSTS); do
		name="host$i.$ZONE.$PROJECT"
		ssh -t $name sudo bash -x -s <<EOF
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9;
echo deb https://get.docker.io/ubuntu docker main > /etc/apt/sources.list.d/docker.list;
apt-get update -qq;
apt-get install -q -y --force-yes --no-install-recommends lxc-docker ethtool;
usermod -a -G docker vagrant;
echo 'DOCKER_OPTS="-H unix:///var/run/docker.sock -H tcp://0.0.0.0:2375"' >> /etc/default/docker;
service docker restart
EOF
		# Add the remote ip to the local /etc/hosts
		sudo -- sh -c "echo \"$(ExternalIPFor host$i) $name\" >>/etc/hosts"
		# Add the local ips to the remote /etc/hosts
		for j in $(seq 1 $NUM_HOSTS); do
			ssh -t $name "sudo -- sh -c \"echo \\\"$(InternalIPFor host$j) host$j.$ZONE.$PROJECT\\\" >>/etc/hosts\""
		done
	done
}

function hosts {
	hosts=
	for i in $(seq 1 $NUM_HOSTS); do
		name="host$i.$ZONE.$PROJECT"
		hosts="$hosts $name"
	done
	echo "$hosts"
}

case "$1" in
setup)
	setup
	;;

hosts)
	hosts
	;;

destroy)
	destroy
	;;
esac
