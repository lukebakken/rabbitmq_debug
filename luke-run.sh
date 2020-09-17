#!/usr/bin/env bash

set -o errexit
set -o nounset
set -x

PATH="$HOME/development/rabbitmq/umbrella/deps/rabbitmq_server_release/sbin:$PATH"

declare -r hostname='shostakovich'
declare -r n1="rabbit-1@$hostname"
declare -r n2="rabbit-2@$hostname"
declare -r n3="rabbit-3@$hostname"

# set up cluster in advance

# enable drop_unroutable_metric feature
docker exec -it node1 rabbitmqctl enable_feature_flag drop_unroutable_metric

# setup admin
rabbitmqctl -n "$n1" add_user admin administrator
rabbitmqctl -n "$n1" set_user_tags admin administrator
rabbitmqctl -n "$n1" set_permissions --vhost / admin '.*' '.*' '.*'

# setup user
rabbitmqctl -n "$n1" add_user user password
rabbitmqctl -n "$n1" set_user_tags user administrator
rabbitmqctl -n "$n1" set_permissions --vhost / user '.*' '.*' '.*'

# setup policy
rabbitmqctl -n "$n1" set_policy ha '^(?!amq\.).*' '{"ha-mode":"all", "ha-sync-mode": "automatic"}' --priority 10 --apply-to all
