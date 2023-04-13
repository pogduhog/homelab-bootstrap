#!/bin/sh

#set -e

LF="$(printf '\nq')"; LF=${LF%q} 
TMP=$(mktemp -d)

clean_up() {
	rm -rv "$TMP"
	exit "$1"
}

trap 'clean_up ${?}' EXIT

msg() {
	echo ">>> $1"
}

GIT_USER="pogduhog"
GIT_HOST="github.com"
GIT_ORG="pogduhog"
GIT_REPO="bootstrap-argocd"
GIT_REPO="homelab-k8s"
SUDO='doas'
BOOTSTRAP_KEY=../keys/bootstrap_key
mkdir ../keys/

install_metallb_manifest() {
	msg "Installing Metallb..."
	mkdir -p apps/metallb
	cat <<-EOF > apps/metallb/addresses.yaml
		apiVersion: metallb.io/v1beta1
		kind: IPAddressPool
		metadata:
		  name: first-pool
		  namespace: metallb-system
		spec:
		  addresses:
		  - 10.0.0.50-10.0.0.70
		---
		apiVersion: metallb.io/v1beta1
		kind: L2Advertisement
		metadata:
		  name: metallb-l2
		  namespace: metallb-system
		spec:
		  ipAddressPools:
		  - first-pool
	EOF
	doas helm repo add metallb https://metallb.github.io/metallb
	doas helm install metallb metallb/metallb --create-namespace --namespace metallb-system 
	doas kubectl apply -f apps/metallb/addresses.yaml
}

install_metallb() {
	echo "Installing Metallb..."
	mkdir -p apps/metallb/base
	cfg_metallb_kustomization > apps/metallb/base/kustomization.yaml
	cfg_metallb_l2_addresses > apps/metallb/base/l2_addresses.yaml
	cfg_metallb_l2_advertise > apps/metallb/base/l2_advertise.yaml
	doas kubectl apply -k apps/metallb/base/
}

cfg_metallb_kustomization() {
	# https://metallb.universe.tf/installation/#installation-with-kustomize
		#- github.com/metallb/metallb/config/native?ref=v0.13.9
	cat <<-EOF 
		apiVersion: kustomize.config.k8s.io/v1beta1
		kind: Kustomization
		
		namespace: metallb-system

		resources:
		  - github.com/metallb/metallb/config/crd?ref=v0.13.9
		  - l2_addresses.yaml
		  - l2_advertise.yaml
	EOF
}

install_flux_cli() {
	echo "Installing flux cli"
	curl -s https://fluxcd.io/install.sh | doas bash
}

generate_ssh_keys() {
	if [ ! -e "$BOOTSTRAP_KEY" ]; then
		ssh-keygen -t ed25519 -f "$BOOTSTRAP_KEY" -N ""
		echo "Add the following read/write deploy key to the target repository:"
		cat "$BOOTSTRAP_KEY".pub
	fi
}

install_flux() {
	generate_ssh_keys
	doas flux bootstrap git \
		--url=ssh://git@$GIT_HOST/$GIT_ORG/$GIT_REPO \
		--branch=main \
		--private-key-file "$BOOTSTRAP_KEY" \ 
		--path=clusters/production
}

case "$1" in 
	install-flux-cli)
		install_flux_cli
		;;
	install-flux)
		install_flux
		;;
	*)	echo "Unknown option $1"
		exit 1
		;;
esac
