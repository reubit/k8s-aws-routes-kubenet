# reubit/k8s-aws-routes-kubenet

## Overview

* Updates multiple AWS routes tables when using `kubenet` in a private VPC topology.
* Also disables source/destination checking on all k8s instances.
* This is an interim solution, pending resolution of: https://github.com/kubernetes/kubernetes/issues/42487

## Usage

* For use with `kops` provisioned k8s clusters with options `--topology private` and `--networking kubenet`.
* Since `kops` doesn't let you pass both the above options at the same time, run your `kops create` command with any other networking mode.
** E.g. `kops create cluster mycluster.fqdn.com --topology private --networking calico ...`
** Before provisioning your cluster (with `kops update cluster ...`), first run `kops edit cluster ...` and change `calico` to `kubenet`
* Once your cluster is up and running (minus a working container network), run the following:
** `kubectl apply -f https://raw.githubusercontent.com/reubit/k8s-aws-routes-kubenet/master/k8s-aws-routes-kubenet.yaml`
* DONE!