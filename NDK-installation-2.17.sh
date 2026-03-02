# download NDK tar from ntnx portal
nkp push bundle  \
--bundle ./ndk-2.1.0.tar,./container-images/konvoy-image-bundle-v2.17.0.tar \
--to-internal-registry-mirror   --kubeconfig nkp-target.conf

nkp create catalog-application \
--url oci://registry.nkp-registry-system.svc.cluster.local:5000/nkp-nutanix-product-catalog/ndk \
--tag 2.1.0 -w kommander-workspace

