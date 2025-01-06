# Global configuration
declare -A HOSTS=(
    ["monitor01"]="86.119.45.32"
    ["osd01"]="86.119.44.63"
    ["osd02"]="86.119.47.59 "
    ["osd03"]="86.119.46.205"
)

# Helper function to get all IPs
get_all_ips() {
    echo "${HOSTS[@]}"
}

# Helper function to get IP by hostname
get_ip_by_hostname() {
    echo "${HOSTS[$1]}"
}


add_orkun_ssh_key(){
    for ip in $(get_all_ips); do
        echo "Adding SSH key to $ip..."
        ssh debian@$ip 'mkdir -p ~/.ssh && echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDpPqc1m0zVtCUErM138z9JkDxhOSSrIXL+luTtI+WUnjhLyx6B0n9bYxhJBUS/ZiAD0BVThkkgKOmNa2a9+hbE2ktgo3tvZaawTSnf4BTWaM1mzwzf/ll5aXGKK35rKkMhgucFs9KOP7jXyIKGIwpECYVNX8tpArNH7f1pzoZnVY2YpeKIsr+v2okUC8l6WUpBWGqlLU+8jbruttHjo8PHVGU0L4MXiKNI3PrLCGLK4XFxdVpDSGfcIJTsV9uQ2Diob365lViz9yUwSIUTl+0/Q7RWP39ko79IKi53WfVZDiEWIWYo1RGgbwRlr87PTZj3rA8LE4CkzX0bLPiG1maT7KvETXlkYcyGJunjt4acF7fuhVa9UsA2QrMDMNwUIKtAxd/3tAb+OpNoNHLezoyWV+EPxoahy664uw1TDC3vjuvTa18QoHldH7mSN7izusASbkbuZm0epk0lhyzCrIG6UX9oBBw1kjIEYEsfPOFjjeWLo29c5wPriQkZRCCjglCpVHnBNX3ztcKyUBPnXKgxrDbx5Hdrck5QJCk9/Ij7LeGwG2UWoei+7mMqWB/no2UJdrkjpePbvCzxN3N9ou9A1uhTVMz+zZUztjKH6GM76wLXQo2xdxKfwTC7b161vWMMxKWnaLG6ays9wIR9tJf6KXhBCnA5dFlZ3/OuFRge1Q== orkun.atasoy@students.fhnw.ch" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
    done
}

# Install Ceph repository and keys
install_ceph_repo() {
    local host=$1
    echo "Installing Ceph repository on $host..."
    
    ssh debian@$host "
        # Add GPG key
        wget -q -O- 'https://download.ceph.com/keys/release.asc' | sudo apt-key add -
        
        # Add Ceph repository (changed from debian-reef to debian-squid)
        CODENAME=\$(lsb_release -sc)
        echo deb https://download.ceph.com/debian-squid/ \$CODENAME main | sudo tee /etc/apt/sources.list.d/ceph.list
        
        # Update package list
        sudo apt-get update
    "
}

upgrade_ceph_to_squid() {
    for ip in $(get_all_ips); do
        echo "Upgrading Ceph to Squid release on $ip..."
        ssh debian@$ip "
            sudo rm /etc/apt/sources.list.d/ceph.list
            echo deb https://download.ceph.com/debian-squid/ \$(lsb_release -sc) main | sudo tee /etc/apt/sources.list.d/ceph.list
            sudo apt update
            sudo apt upgrade ceph ceph-mds -y
        "
        echo "Upgrade completed on $ip"
    done
}

# Install Ceph packages
install_ceph_packages() {
    local host=$1
    echo "Installing Ceph packages on $host..."
    
    ssh debian@$host "
        sudo apt-get install -y ceph ceph-mds
    "
}

# Install Ceph on all nodes
install_ceph_on_all_nodes() {
    for ip in $(get_all_ips); do
        echo "Installing Ceph on $ip..."
        install_ceph_repo $ip
        install_ceph_packages $ip
    done
}

install_docker_on_remote() {
    local host=$1
    echo "Installing Docker on $host..."
    
    # Execute Docker installation commands remotely 
    ssh debian@$host '
        # Add Docker'"'"'s official GPG key:
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository to Apt sources:
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    '
    
    echo "Docker installation completed on $host"
}

install_docker_on_all_nodes() {
    for ip in $(get_all_ips); do
        install_docker_on_remote "$ip"
    done

    echo "Docker installation completed on all nodes"
}


bootstrap_monitor() {
    local monip="10.0.5.77"
    echo "Bootstrapping cluster on Monitor01 ($monip)..."
    ssh debian@$monip "sudo cephadm bootstrap --mon-ip $monip"
}


add_orch_host_to_cluster() {
    local monitor_ip="86.119.45.32"
    local osd_hosts=(
        "osd01:86.119.44.63"
        "osd02:86.119.47.59 "
        "osd03:86.119.46.205"
    )

    echo "Adding hosts to the Ceph cluster..."

    # Add each host to the cluster
    for host_entry in "${osd_hosts[@]}"; do
        local hostname="${host_entry%%:*}"
        local ip="${host_entry#*:}"
        
        echo "Adding $hostname ($ip) to the cluster..."
        ssh debian@${monitor_ip} "sudo ceph orch host add $hostname $ip"
    done

    # Display available devices
    echo "Checking available devices..."
    ssh debian@${monitor_ip} "sudo ceph orch device ls"
}


generate_and_add_ssh_keys() {
    local monitor_ip="86.119.45.32"
    local osd_hosts=(
        "86.119.44.63"  # osd01
        "86.119.47.59 "  # osd02
        "86.119.46.205"  # osd03
    )

    # Generate SSH key pair on Monitor01
    echo "Generating SSH key pair on Monitor01..."
    ssh debian@${monitor_ip} "
        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -q
        chmod 600 ~/.ssh/id_ed25519*
    "

    # Get the public key content
    local pub_key=$(ssh debian@${monitor_ip} "cat ~/.ssh/id_ed25519.pub")

    # Add the public key to each OSD host
    for host in "${osd_hosts[@]}"; do
        echo "Adding SSH key to $host..."
        ssh debian@${host} "
            mkdir -p ~/.ssh
            echo '$pub_key' >> ~/.ssh/authorized_keys
            chmod 700 ~/.ssh
            chmod 600 ~/.ssh/authorized_keys
        "
    done

    echo "SSH keys have been generated and distributed to all hosts"
}

#########################
# Task 2
#########################

create_rbd_pool() {
    echo "Creating RBD pool..."
    # Create the pool with the specified name
    ssh debian@86.119.45.32 'sudo cephadm shell -- ceph osd pool create 01-rbd-cloudfhnw'
    
    # Enable PG autoscaling for the pool
    ssh debian@86.119.45.32 'sudo cephadm shell -- ceph osd pool set 01-rbd-cloudfhnw pg_autoscale_mode on'
    
    # Initialize the pool for RBD use
    ssh debian@86.119.45.32 'sudo cephadm shell -- rbd pool init 01-rbd-cloudfhnw'
    
    echo "RBD pool created and initialized"
}

create_rbd_client() {
    echo "Creating RBD client..."
    # Create client with appropriate permissions
    ssh debian@86.119.45.32 'sudo cephadm shell -- ceph auth get-or-create client.01-cloudfhnw-rbd \
        mon '\''profile rbd'\'' \
        osd '\''profile rbd pool=01-rbd-cloudfhnw'\'' \
        mgr '\''profile rbd pool=01-rbd-cloudfhnw'\'
    
    # Verify client creation
    echo "Verifying client creation:"
    ssh debian@86.119.45.32 'sudo cephadm shell -- ceph auth get client.01-cloudfhnw-rbd'
    
    echo "RBD client created"
}

create_rbd_image() {
    echo "Creating RBD image..."
    # Create 2GB image in the pool
    ssh debian@86.119.45.32 'sudo cephadm shell -- rbd create --size 2048 01-rbd-cloudfhnw/01-cloudfhnw-cloud-image'
    
    # Verify image creation
    echo "Verifying image creation:"
    ssh debian@86.119.45.32 'sudo cephadm shell -- rbd ls 01-rbd-cloudfhnw'
    
    echo "RBD image created"
}


create_cephfs() {
    echo "Creating CephFS filesystem..."
    # Create the filesystem with the specified name
    ssh debian@86.119.45.32 'sudo cephadm shell -- ceph fs volume create cephfs-cloudfhnw'
    
    echo "Verifying filesystem creation:"
    ssh debian@86.119.45.32 'sudo cephadm shell -- ceph fs ls'
    
    echo "CephFS filesystem created"
}

create_cephfs_client() {
    echo "Creating CephFS client..."
    
    # Remove existing client if it exists (to avoid conflicts)
    ssh debian@86.119.45.32 'sudo cephadm shell -- ceph auth del client.02-cloudfhnw-cephfs 2>/dev/null'
    
    # Create and authorize the client with read/write access to root
    ssh debian@86.119.45.32 'sudo cephadm shell -- ceph fs authorize cephfs-cloudfhnw client.02-cloudfhnw-cephfs / rw'
    
    # Verify client creation and permissions
    echo "Verifying client creation and permissions:"
    ssh debian@86.119.45.32 'sudo cephadm shell -- ceph auth get client.02-cloudfhnw-cephfs'
    
    echo "CephFS client created with read/write access"
}


main() {
    while true; do
        echo "Choose an option:"
        echo "1) Say moin"
        echo "2) Add SSH key of orkun"
        echo "3) Install docker"
        echo "4) Install Ceph"
        echo "5) Bootstrap monitor cluster"
        echo "6) Generate SSH key and add to all hosts"
        echo "7) Setup Ceph cluster"
        echo "8) Create RBD pool"
        echo "9) Create RBD client"
        echo "10) Create RBD image"
        echo "11) Create CephFS filesystem"
        echo "12) Create CephFS client"
        echo "42) Exit"

        read -p "Press the key for the choice: " choice
        case $choice in
            1) upgrade_ceph_to_squid ;;
            2) add_orkun_ssh_key ;;
            3) 
                for ip in $(get_all_ips); do
                    install_docker_on_remote $ip
                done
                ;;
            4) install_ceph_on_all_nodes ;;
            5) bootstrap_monitor ;;
            6) generate_and_add_ssh_keys ;;
            7) setup_ceph_cluster ;;
            8) create_rbd_pool ;;
            9) create_rbd_client ;;
            10) create_rbd_image ;;
            11) create_cephfs ;;
            12) create_cephfs_client ;;
            42) echo "Exit"; exit ;;
            *) echo "Invalid choice. Please enter a valid option." ;;
        esac
    done
}


# Call main
main