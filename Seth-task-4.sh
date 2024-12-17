add_orkun_ssh_key(){
    ssh debian@86.119.30.12 'mkdir -p ~/.ssh && echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDpPqc1m0zVtCUErM138z9JkDxhOSSrIXL+luTtI+WUnjhLyx6B0n9bYxhJBUS/ZiAD0BVThkkgKOmNa2a9+hbE2ktgo3tvZaawTSnf4BTWaM1mzwzf/ll5aXGKK35rKkMhgucFs9KOP7jXyIKGIwpECYVNX8tpArNH7f1pzoZnVY2YpeKIsr+v2okUC8l6WUpBWGqlLU+8jbruttHjo8PHVGU0L4MXiKNI3PrLCGLK4XFxdVpDSGfcIJTsV9uQ2Diob365lViz9yUwSIUTl+0/Q7RWP39ko79IKi53WfVZDiEWIWYo1RGgbwRlr87PTZj3rA8LE4CkzX0bLPiG1maT7KvETXlkYcyGJunjt4acF7fuhVa9UsA2QrMDMNwUIKtAxd/3tAb+OpNoNHLezoyWV+EPxoahy664uw1TDC3vjuvTa18QoHldH7mSN7izusASbkbuZm0epk0lhyzCrIG6UX9oBBw1kjIEYEsfPOFjjeWLo29c5wPriQkZRCCjglCpVHnBNX3ztcKyUBPnXKgxrDbx5Hdrck5QJCk9/Ij7LeGwG2UWoei+7mMqWB/no2UJdrkjpePbvCzxN3N9ou9A1uhTVMz+zZUztjKH6GM76wLXQo2xdxKfwTC7b161vWMMxKWnaLG6ays9wIR9tJf6KXhBCnA5dFlZ3/OuFRge1Q== orkun.atasoy@students.fhnw.ch" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
}

setup_ceph_cluster() {
    echo "Starting Ceph cluster setup..."

    # Define the hostnames or IP addresses of the nodes
    MONITOR_NODE="86.119.30.12"       # Replace with your monitor node's IP or hostname
    OSD_NODES=("86.119.31.236" "86.119.30.244" "86.119.30.199")  # Replace with your OSD nodes' IPs or hostnames

    # Install cephadm on monitor node 
    echo "Installing cephadm on $MONITOR_NODE..."

    ssh debian@$MONITOR_NODE "
        curl --silent --remote-name --location https://download.ceph.com/cephadm/cephadm &&
        chmod +x cephadm &&
        ./cephadm add-repo --release quincy &&
        ./cephadm install
    "

    # Get the IP address of the monitor node
    MONITOR_IP=$(ssh debian@$MONITOR_NODE "hostname -I | awk '{print \$1}'")

    # Bootstrap the cluster
    echo "Bootstrapping the Ceph cluster..."
    ssh debian@$MONITOR_NODE "./cephadm bootstrap --mon-ip $MONITOR_IP"

    # Add OSD nodes to the cluster
    for node in "${OSD_NODES[@]}"; do
        echo "Adding host $node to cluster..."
        ssh debian@$MONITOR_NODE "ceph orch host add $node"

        # Label the host with 'osd'
        echo "Labeling host $node with 'osd'..."
        ssh debian@$MONITOR_NODE "ceph orch host label add $node osd"
    done

    # Deploy OSDs on available devices with --method raw
    echo "Deploying OSDs on all available devices with --method raw..."
    ssh debian@$MONITOR_NODE "ceph orch apply osd --all-available-devices --method raw"

    echo "Ceph cluster setup complete."
}


main() {
    while true; do
        echo "Choose an option:"
        echo "1)  say_moin"
        echo "2) add ssh key of orkun"
        echo "3) Setup Ceph cluster"
        echo "42)  exit"

        read -p "Press the key for the choice: " choice
        case $choice in
            1) say_moin ;;
            2) add_orkun_ssh_key ;;
            3) setup_ceph_cluster ;;
           42) echo "Exit"; exit ;;
            *) echo "Invalid choice. Please enter a valid option." ;;
        esac
    done
}


# Call main
main