#!/bin/bash

routes=$(kubectl get nodes -o json | jq '.items | .[] | .spec.podCIDR, .spec.externalID' -r | xargs | sed 's/\([^ ]\+\) \([^ ]\+\) /\1 \2\n/g')

instances_json=$(echo "$routes" | awk '{ print $2 }' | xargs aws ec2 describe-instances --instance-ids)

subnets=$(echo "$instances_json" | jq '.Reservations | .[] | .Instances | .[] | .NetworkInterfaces | .[] | .SubnetId' -r)

tables_json=$(aws ec2 describe-route-tables)

route_tables=$(
  for each in $subnets; do 
    echo "$tables_json" | jq '.RouteTables | .[] | select(.Associations | .[] | .SubnetId == "'${each}'") | .RouteTableId' -r
  done | sort -u
)

commands=$(
for table in $route_tables; do
  OIFS=$IFS; IFS=$'\n'

  blackhole_routes=$(echo "$tables_json" | jq '.RouteTables | .[] | select(.RouteTableId == "'${table}'") | .Routes | .[] | select(.State == "blackhole") | .DestinationCidrBlock' -r)
  for blackhole in $blackhole_routes; do
    # Delete blackhole routes that we don't have a replacement route for
    echo "$routes" | grep $blackhole || echo "aws ec2 delete-route --route-table-id $table --destination-cidr-block $blackhole"
  done

  for route in $routes; do
    cidr=$(echo "$route" | awk '{ print $1}')
    instance_id=$(echo "$route" | awk '{ print $2}')

    source_dest_check=$(echo "$instances_json" | jq '.Reservations | .[] | .Instances | .[] | select(.InstanceId == "'${instance_id}'") | .SourceDestCheck')

    if [ "$source_dest_check" == "true" ]; then
      echo "aws ec2 modify-instance-attribute --instance-id ${instance_id} --no-source-dest-check"
    fi

    check_cidr=$(echo "$tables_json" | jq '.RouteTables | .[] | select(.RouteTableId == "'${table}'") | .Routes | .[] | select(.DestinationCidrBlock == "'${cidr}'") | .DestinationCidrBlock' -r)
    if [ "$cidr" == "$check_cidr" ]; then

      check_route_instance_id=$(echo "$tables_json" | jq '.RouteTables | .[] | select(.RouteTableId == "'${table}'") | .Routes | .[] | select(.DestinationCidrBlock == "'${cidr}'") | .InstanceId' -r)
      if [ "$instance_id" != "$check_route_instance_id" ]; then
        echo "$table $route" | awk '{ print "aws ec2 replace-route --route-table-id " $1 " --destination-cidr-block " $2 " --instance-id " $3}'
      fi

    else
      echo "$table $route" | awk '{ print "aws ec2 create-route --route-table-id " $1 " --destination-cidr-block " $2 " --instance-id " $3}'
    fi
  done
  IFS=$OIFS
done | sort -u
)

OIFS=$IFS; IFS=$'\n'
for command in $commands; do
  echo "$command"
  if [ "$1" == "--yes" ]; then
    eval "$command" && echo 'Success!' || echo 'Failed!'
    echo
  fi
done
IFS=$OIFS

