#!/usr/bin/env bash

set -o errexit
set -o nounset
set -x

PATH="$HOME/development/rabbitmq/umbrella/deps/rabbitmq_server_release/sbin:$PATH"

declare -r hostname='shostakovich'
declare -r n1="rabbit-1@$hostname"
declare -r n2="rabbit-2@$hostname"
declare -r n3="rabbit-3@$hostname"
declare -r rpc_flood_pid_file="$(mktemp)"
declare -r rpc_flood_client_pid_file="$(mktemp)"

trap "{ rm -f $rpc_flood_pid_file $rpc_flood_client_pid_file }" EXIT

# set up cluster in advance

# python3 -m pip install requests pika
source "$PWD/venv/bin/activate"

check_cluster()
{
    echo
    echo "# check_rabbitmq_unroutable_msg"
    echo "###############################"
    "$PWD/check_rabbitmq_unroutable_msg" "$PWD/config.ini.default"

    echo
    echo "# wip_detect_broken_bindings"
    echo "############################"
    "$PWD/wip_detect_broken_bindings"

    echo
    echo "# wip_detect_broken_queues"
    echo "##########################"
    "$PWD/wip_detect_broken_queues"
}

genload()
{
    local -i genload_id=0
    for rpc_flood_id in $(seq 1 $(nproc))
    do
        echo "[INFO] starting rpc_flood id $rpc_flood_id"
        "$PWD/rpc_flood" &
        echo "$!" >> "$rpc_flood_pid_file"
    done

    for rpc_flood_client_id in $(seq 1 75)
    do
        echo "[INFO] starting rpc_flood_client id $rpc_flood_client_id"
        "$PWD/rpc_flood_client" &
        echo "$!" >> "$rpc_flood_client_pid_file"
    done
}

# enable drop_unroutable_metric feature
rabbitmqctl -n "$n1" enable_feature_flag drop_unroutable_metric

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

check_cluster

genload

sleep 60

rabbitmqctl -n "$n2" shutdown

sleep 10

stop_genload

check_cluster