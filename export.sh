#!/bin/bash

cassandra_info(){
    pids="`pgrep java`"
    for pid in "$pids" ; do
        cwds=`lsof -p $pid | grep cwd | awk '{print $9}'`
        for cwd in "$cwds" ; do
            if [ -f "$cwd/cassandra" ] ; then
                echo "Cassandra seems to be running with pid $pid (this is my best guess)"
                echo "For higher confidence results, please set CASSANDRA_HOME environment variable"
                CASSANDRA_HOME="`dirname $cwd`"
                CASSANDRA_PID="$pid"
            fi
        done
    done
}

locate_nodetool() {
    # can we just use nodetool, ie, is it in $PATH ?
    if [ ! -f "`which nodetool`" ] ; then
        # not found, so we need to find CASSANDRA_HOME first. Is it set?
        if [ ! -f "$CASSANDRA_HOME" ] ; then
            # it isn't, we need to guess everything
            cassandra_info
        fi
        NODETOOL="$CASSANDRA_HOME/bin/nodetool"
    else
        # nodetool is in $PATH, let's just use that
        NODETOOL="`which nodetool`"
    fi
    # at this stage NODETOOL must be set, if it isn't i couldn't find it
    if [ -z "$NODETOOL" ] ; then
        echo "Cassandra nodetool couldn't be located. Please include it in your PATH or set CASSANDRA_HOME"
        exit 1
    fi
}

snapshot_nodetool(){
    echo "Taking snapshot of cassandra current state"
    NODETOOL_LOG="/tmp/nodetool-snapshot.log"
    $NODETOOL snapshot &> $NODETOOL_LOG
}

snapshot_store(){
    echo "Determining latest snapshot..."
    while read line ; do
        if [[ "$line" == *directory* ]] ; then
            snapshot_number="echo $line | awk {'print $3'}"
        fi
    done < $NODETOOL_LOG
    snapshot_paths=$(find $CASSANDRA_HOME -type d -iname "$snapshot_number")
    if [ ! -z "$snapshot_paths" ] ; then
        for snapshot in $snapshot_paths ; do
        done
    else
        echo "Couldn't determine snapshot number. I'm confused. Abort."
        exit 2
    fi

}



locate_nodetool
snapshot_store
snapshot_pack
