Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        # This handles your specific Nutanix lab host
        hosts {
           10.161.83.150 dso-mgt.ntnxlab.local
           fallthrough
        }
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        # CHANGE THIS LINE BELOW:
        forward . 10.161.83.150 {
           max_concurrent 1000
        }
        cache 30 {
           disable success cluster.local
           disable denial cluster.local
        }
        loop
        reload
        loadbalance
    }