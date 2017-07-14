# k8s-aws-routes-kubenet
Updates multiple aws routes tables for use with private AWS VPC topologies.

For use with kubenet when using multiple route tables in a private topology.

Also disables source/destination checking on k8s instances.

This is an interim solution, pending resolution of: https://github.com/kubernetes/kubernetes/issues/42487
