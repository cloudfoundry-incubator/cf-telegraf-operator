#!/bin/bash
set -exo pipefail

telegraf_dir=$(cd $(dirname ${BASH_SOURCE}) && pwd)

function create_security_group() {
  echo "Creating Telegraf scrape security group"

  if ! cf security-group telegraf-scrape > /dev/null ; then
    cf create-security-group telegraf-scrape "${telegraf_dir}/asg.json"
  else
    cf update-security-group telegraf-scrape "${telegraf_dir}/asg.json"
  fi

  cf bind-security-group telegraf-scrape system system
}

function download_telegraf() {
  telegraf_version=$(curl -s https://api.github.com/repos/influxdata/telegraf/releases/latest | jq -r .tag_name || "1.12.6")
  telegraf_version_stripped=${telegraf_version#"v"}
  telegraf_binary_url="https://dl.influxdata.com/telegraf/releases/telegraf-${telegraf_version_stripped}-static_linux_amd64.tar.gz"
  # TODO: Fix tar step
  wget -qO- "$telegraf_binary_url" | tar xvz --strip=1 telegraf/
}

function create_certificates() {
  mkdir -p certs
  pushd certs > /dev/null
   # Grab the Credhub path of the metric_scraper_ca
    ca_cert_name=$(credhub find -n metric_scraper_ca --output-json | jq -r .credentials[].name | grep cf)
    credhub generate -n telegraf_scrape_tls -t certificate --ca "$ca_cert_name" -c telegraf_scrape_tls

    credhub get -n telegraf_scrape_tls --output-json | jq -r .value.ca > scrape_ca.crt
    credhub get -n telegraf_scrape_tls --output-json | jq -r .value.certificate > scrape.crt
    credhub get -n telegraf_scrape_tls --output-json | jq -r .value.private_key > scrape.key

   # Grab the Credhub path of the nats_ca and nats_client_cert
    nats_ca_name=$(credhub find -n nats_ca --output-json | jq -r .credentials[].name | grep cf)
    nats_client_name=$(credhub find -n nats_client_cert --output-json | jq -r .credentials[].name | grep cf)
    credhub get -n "$nats_ca_name" --output-json | jq -r .value.ca > nats_ca.crt
    credhub get -n "$nats_client_name" --output-json | jq -r .value.certificate > nats.crt
    credhub get -n "$nats_client_name" --output-json | jq -r .value.private_key > nats.key
  popd > /dev/null
}

function push_telegraf() {
  cf target -o system -s system

  GOOS=linux go build -o confgen
  cf v3-create-app telegraf
  #cf set-env telegraf NATS_HOSTS "$(bosh instances --column Instance --column IPs | grep nats | awk '{print $2}' | grep -v "-")"
  cf set-env telegraf NATS_HOSTS "nats.service.cf.internal"

  nats_cred_name=$(credhub find --name-like nats_password --output-json | jq -r .credentials[0].name)
  cf set-env telegraf NATS_PASSWORD "$(credhub get --name ${nats_cred_name} --quiet)"

  cf v3-apply-manifest -f "${telegraf_dir}/manifest.yml"
  cf v3-push telegraf
}

pushd ${telegraf_dir} > /dev/null
#  download_telegraf
  create_security_group
  create_certificates
  push_telegraf
popd > /dev/null
