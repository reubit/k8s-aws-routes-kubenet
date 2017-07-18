#!/bin/bash

# Get a list of CIDR-to-InstanceId mappings for all k8s nodes
routes=$(kubectl get nodes -o json | \
  jq '.items | .[] | .spec.podCIDR, .spec.externalID' -r | \
  xargs | \
  sed 's/\([^ ]\+\) \([^ ]\+\) /\1 \2\n/g')

# Get "describe-instances" JSON blob for our set of instance ids
instances_json=$(echo "$routes" | \
  awk '{ print $2 }' | \
  xargs aws ec2 describe-instances --instance-ids)

# Lookup list of all subnets associated with our instances
subnets=$(echo "$instances_json" | \
  jq '.Reservations | .[] | .Instances | .[] | .NetworkInterfaces | .[] | .SubnetId' -r)

# Get "describe-route-tables" JSON blob for all route tables
tables_json=$(aws ec2 describe-route-tables)

# Lookup all route tables that are associated with our instances' subents
route_tables=$(
  for each in $subnets; do 
    echo "$tables_json" | jq '.RouteTables | .[] | select(.Associations | .[] | .SubnetId == "'"${each}"'") | .RouteTableId' -r
  done | sort -u)

OIFS=$IFS
IFS='
'

# Generate list of commands to print (or run if --yes), for each route table
commands=$(
for table in $route_tables; do

  # Lookup routes in this route table with: State == "blackhole"
  blackhole_routes=$(echo "$tables_json" | \
    jq '.RouteTables | .[] | select(.RouteTableId == "'"${table}"'") | .Routes | .[] | select(.State == "blackhole") | .DestinationCidrBlock' -r)

  # Generate "delete-route" commands for all blackhole routes in this table
  for blackhole in $blackhole_routes; do
    # Only delete blackhole routes that we don't have a replacement route for
    echo "$routes" | grep "$blackhole" \
      || echo "aws ec2 delete-route --route-table-id $table --destination-cidr-block $blackhole"
  done

  # Check for routes that need replacing or creating
  for route in $routes; do

    cidr=$(echo "$route" | awk '{ print $1}')
    instance_id=$(echo "$route" | awk '{ print $2}')

    # Disable source/destination checking if enabled
    source_dest_check=$(echo "$instances_json" | \
      jq '.Reservations | .[] | .Instances | .[] | select(.InstanceId == "'"${instance_id}"'") | .SourceDestCheck')
    if [ "$source_dest_check" = "true" ]; then
      echo "aws ec2 modify-instance-attribute --instance-id ${instance_id} --no-source-dest-check"
    fi

    # IF a route already exists for this CIDR, print a "replace-route" command 
    # ELSE, print a "create-route" command.
    check_cidr=$(echo "$tables_json" | \
      jq '.RouteTables | .[] | select(.RouteTableId == "'"${table}"'") | .Routes | .[] | select(.DestinationCidrBlock == "'"${cidr}"'") | .DestinationCidrBlock' -r)
    if [ "$cidr" = "$check_cidr" ]; then
      check_route_instance_id=$(echo "$tables_json" | \
        jq '.RouteTables | .[] | select(.RouteTableId == "'"${table}"'") | .Routes | .[] | select(.DestinationCidrBlock == "'"${cidr}"'") | .InstanceId' -r)
      if [ "$instance_id" != "$check_route_instance_id" ]; then
        echo "aws ec2 replace-route --route-table-id $table --destination-cidr-block $cidr --instance-id $instance_id"
      fi
    else
      echo "aws ec2 create-route --route-table-id $table --destination-cidr-block $cidr --instance-id $instance_id"
    fi

  done
done | sort -u)

# Echo all generated commands and execute them if "--yes" was passed
for command in $commands; do
  echo "$command"
  if [ "$1" = "--yes" ]; then
    eval "$command" && echo 'Success!' || echo 'Failed!'
    echo
  fi
done

IFS=$OIFS
