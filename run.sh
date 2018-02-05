#!/bin/sh

file=$1
hosts=/run/openshift/label.tmp.hosts
inventory_file_path=$2
label_prefix="role"
pbench_label="type=pbench"
inv_path=$3
declare -a host
declare -a group
declare -a label

# Check for kubeconfig
if [[ ! -s $HOME/.kube/config ]]; then
	echo "cannot find kube config in the home directory, please check"
	exit 1
fi

# Check if oc client is installed
which oc &>/dev/null
echo "Checking if oc client is installed"
if [[ $? != 0 ]]; then
	echo "oc client is not installed"
	echo "installing oc client"
 	curl -L https://github.com/openshift/origin/releases/download/v1.2.1/openshift-origin-client-tools-v1.2.1-5e723f6-linux-64bit.tar.gz | tar -zx && \
    	mv openshift*/oc /usr/local/bin && \
	rm -rf openshift-origin-client-tools-*
else
	echo "oc client already present"
fi

if [[ -z $inv_path ]]; then
	inv_path="/root/tooling_inventory"
	echo "inventory path is not provided by the user, the inventory will be generated in the default location /root/inventory"
fi

function generate_inventory() {
	# pbench-controller
	echo "[pbench-controller]" > $inv_path
	echo $(hostname) >> $inv_path

	# masters
	echo "[masters]" >> $inv_path
	for nodes in $(oc get nodes -l role=master -o json | jq '.items[].metadata.name'); do
        	echo $nodes |  sed "s/\"//g" >> $inv_path
	done

	# nodes
	echo "[nodes]" >> $inv_path
	for nodes in $(oc get nodes -l role=node -o json | jq '.items[].metadata.name'); do
        	echo $nodes |  sed "s/\"//g" >> $inv_path
	done

	# etcd
	echo "[etcd]" >> $inv_path
	for nodes in $(oc get nodes -l role=etcd -o json | jq '.items[].metadata.name'); do
        	echo $nodes |  sed "s/\"//g" >> $inv_path
	done

	# lb
	echo "[lb]" >> $inv_path
	for nodes in $(oc get nodes -l role=lb -o json | jq '.items[].metadata.name'); do
        	echo $nodes |  sed "s/\"//g" >> $inv_path
	done
}

while read -u 9 line;do
  hostname=$(echo $line | awk -F' ' '{print $1}')
  group_name=$(echo $line | awk -F' ' '{print $2}')
  label_name="$group_name"
  host[${#host[@]}]=$hostname
  group[${#group[@]}]=$group_name
  label[${#label[@]}]=$label_name
done 9< $file
array_length=${#host[*]}
for ((i=0; i<$array_length; i++));do
  for ((j=i+1; j<$array_length; j++));do
    if [[ ${host[i]} == ${host[j]} ]] && [[ ${host[i]} != '' ]]; then
      label[i]=$(echo ${label[i]}_${group[j]})
      unset label[j]
      unset host[j]
      unset group[j]
    fi
  done
  if [[ ${host[i]} != '' ]]; then
    echo ${host[i]} ${group[i]} ${label[i]} >> $hosts
  fi
done
while read -u 11 line;do
  host=$(echo $line | awk -F' ' '{print $1}')
  group=$(echo $line | awk -F' ' '{print $2}')
  label=$(echo $line | awk -F' ' '{print $3}')
  # unlabel the node in case it's already labeled
  oc label node $host $label_prefix-
  oc label node $host $label_prefix"="$label
  # label the node on which we want to run pbench pods
  oc label node $host $pbench_label
done 11< $hosts
## delete host files
/bin/rm $file
if [ $? -ne 0 ]; then
  warn_log "cannot delete input file" 
fi
/bin/rm $hosts
if [ $? -ne 0 ]; then
  warn_log "cannot delete hosts file" 
fi
# generate inventory
generate_inventory
exit 0
