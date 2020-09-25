#!/usr/bin/env bash

set -o errexit
set -o nounset

PATH="$HOME/development/rabbitmq/umbrella/deps/rabbitmq_server_release/sbin:$PATH"

declare -r hostname='shostakovich'
declare -ri port=15672
declare -r n1="rabbit-1@$hostname"
declare -r n2="rabbit-2@$hostname"
declare -r n3="rabbit-3@$hostname"

declare -r rpc_flood_pid_file="$(mktemp)"
declare -r rpc_flood_client_pid_file="$(mktemp)"
declare -ri rpc_flood_client_count='128'

declare -ri sleep_one=60
declare -ri sleep_two=10

declare -r ex_unroutable='unroutable'
declare -r q_unroutable_messages='unroutable_messages'

trap "{ rm -f $rpc_flood_pid_file $rpc_flood_client_pid_file; }" EXIT

# set up cluster in advance

# python3 -m pip install requests pika
source "$PWD/venv/bin/activate"

setup_cluster()
{
    set +o errexit
    rabbitmqctl -n "$n1" enable_feature_flag drop_unroutable_metric

    rabbitmqctl -n "$n1" add_user admin administrator
    rabbitmqctl -n "$n1" set_user_tags admin administrator
    rabbitmqctl -n "$n1" set_permissions --vhost / admin '.*' '.*' '.*'

    rabbitmqctl -n "$n1" add_user user password
    rabbitmqctl -n "$n1" set_user_tags user administrator
    rabbitmqctl -n "$n1" set_permissions --vhost / user '.*' '.*' '.*'
    set -o errexit

    rabbitmqctl -n "$n1" set_policy 'ha_rpc' '^rpc_' "{\"ha-mode\":\"all\",\"ha-sync-mode\":\"automatic\",\"alternate-exchange\":\"$ex_unroutable\"}" --priority 10 --apply-to queues
    rabbitmqctl -n "$n1" set_policy 'ha_unroutable' "^$q_unroutable_messages$" "{\"ha-mode\":\"all\",\"ha-sync-mode\":\"automatic\"}" --priority 10 --apply-to queues

    # create unroutable exchange
    rabbitmqadmin declare exchange name="$ex_unroutable" type='fanout' auto_delete='false' durable='true'

    # create unroutable_messages queue
    rabbitmqadmin declare queue name="$q_unroutable_messages" auto_delete='false' durable='true' arguments='{"x-message-ttl": 300000}'

    # bind unroutable_messages to unroutable exchange
    rabbitmqadmin declare binding source="$ex_unroutable" destination="$q_unroutable_messages" destination_type='queue'
}

check_cluster()
{
    set +o errexit
    echo
    echo "# check_rabbitmq_unroutable_msg"
    echo "###############################"
    "$PWD/check_rabbitmq_unroutable_msg" "$PWD/config.ini.default"

    echo
    echo "# detect_broken_bindings"
    echo "############################"
    "$PWD/detect_broken_bindings"

    echo
    echo "# detect_broken_queues"
    echo "##########################"
    "$PWD/detect_broken_queues"
    set -o errexit
}

genload()
{
    set +o errexit
    rm -f "$PWD"/output/*.txt
    set -o errexit

    for rpc_flood_id in $(seq 1 "$(nproc)")
    do
        echo "[INFO] starting rpc_flood id $rpc_flood_id"
        "$PWD/rpc_flood" > "$PWD/output/rpc_flood-$rpc_flood_id-out.txt" 2>&1 &
        echo "$!" >> "$rpc_flood_pid_file"
    done

    for rpc_flood_client_id in $(seq 1 "$rpc_flood_client_count")
    do
        echo "[INFO] starting rpc_flood_client id $rpc_flood_client_id"
        "$PWD/rpc_flood_client" > "$PWD/output/rpc_flood_client-$rpc_flood_client_id-out.txt" 2>&1 &
        echo "$!" >> "$rpc_flood_client_pid_file"
    done
}

kill_processes()
{
    set +o errexit
    local pid_file="$1"
    while IFS= read -r pid
    do
        # echo "[INFO] stopping process $pid"
        kill -TERM "$pid" 2> /dev/null
    done < "$pid_file"
    set -o errexit
}

stop_genload()
{
    kill_processes "$rpc_flood_pid_file"
}

stop_genload_clients()
{
    kill_processes "$rpc_flood_client_pid_file"
}

do_sleep()
{
    local -ri s="$1"
    echo "[INFO] sleeping $s seconds"
    sleep "$s"
}

setup_cluster

check_cluster

genload

do_sleep "$sleep_one"

rabbitmqctl -n "$n2" shutdown

do_sleep "$sleep_two"

stop_genload

check_cluster

stop_genload_clients
