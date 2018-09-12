# redis-cluster-k8s
redis cluster in kubernets

# Raady work:  
glusterfs:  
192.168.3.2  
192.168.3.4  
1,  
yum install centos-release-gluster -y  
yum install -y glusterfs glusterfs-server glusterfs-fuse glusterfs-rdma glusterfs-geo-replication glusterfs-devel  
mkdir /opt/glusterd  
修改 glusterd 目录  
sed -i 's/var\/lib/opt/g' /etc/glusterfs/glusterd.vol  
启动 glusterfs  
systemctl start glusterd.service  
systemctl enable glusterd.service  
  
2,  
gluster peer probe 192.168.3.2  
gluster peer status  
创建 glusterfs 复制卷  
gluster volume create gfs-volume replica 2 transport tcp 192.168.3.4:/opt/gfs_data 192.168.3.2:/opt/gfs_data force  
gluster volume info  
  
3,  
在所有 k8s node 中安装 glusterfs 客户端  
yum install -y glusterfs glusterfs-fuse  
gluster volume info  
gluster volume start/state/stop/delete <volume-name>  
  
WARNING:  
如果想要在文件里面挂载: gfs_data/ 目录下挂载  
需要在所有服务器 的目录下创建目录  
168.168.3.2 / 3.4 gfs_data目录下 mkdir redis0 redis1 redis2  

# Cluster init
docker build -t tag yourImage .  
kubectl create -f glusterfs-endpoints.yaml  
kubectl create -f pv.yaml
kubectl apply -f redis-cluster.yml  
kubectl exec -it redis-cluster-0 -- redis-cli --cluster create --cluster-replicas 1 \  
$(kubectl get pods -l app=redis-cluster -o jsonpath='{range.items[*]}{.status.podIP}:6379 ')  

---  redis-5.0-rc redis-cli 集成 redis-trib.rb 功能 ---  
# Adding nodes
Adding nodes to the cluster involves a few manual steps. First, let's add two nodes:

kubectl scale statefulset redis-cluster --replicas=8
Have the first new node join the cluster as master:

kubectl exec redis-cluster-0 -- redis-cli --cluster add-node \
$(kubectl get pod redis-cluster-6 -o jsonpath='{.status.podIP}'):6379 \
$(kubectl get pod redis-cluster-0 -o jsonpath='{.status.podIP}'):6379
The second new node should join the cluster as slave. This will automatically bind to the master with the least slaves (in this case, redis-cluster-6)

kubectl exec redis-cluster-0 -- redis-cli --cluster add-node --cluster-slave \
$(kubectl get pod redis-cluster-7 -o jsonpath='{.status.podIP}'):6379 \
$(kubectl get pod redis-cluster-0 -o jsonpath='{.status.podIP}'):6379  

Finally, automatically rebalance the masters:  

kubectl exec redis-cluster-0 -- redis-cli --cluster rebalance --cluster-use-empty-masters \
$(kubectl get pod redis-cluster-0 -o jsonpath='{.status.podIP}'):6379
# Removing nodes
## Removing slaves
Slaves can be deleted safely. First, let's get the id of the slave:

$ kubectl exec redis-cluster-7 -- redis-cli cluster nodes | grep myself
3f7cbc0a7e0720e37fcb63a81dc6e2bf738c3acf 172.17.0.11:6379 myself,slave 32f250e02451352e561919674b8b705aef4dbdc6 0 0 0 connected
Then delete it:

kubectl exec redis-cluster-0 -- redis-cli --cluster del-node \
$(kubectl get pod redis-cluster-0 -o jsonpath='{.status.podIP}'):6379 \
3f7cbc0a7e0720e37fcb63a81dc6e2bf738c3acf
## Removing a master
To remove master nodes from the cluster, we first have to move the slots used by them to the rest of the cluster, to avoid data loss.

First, take note of the id of the master node we are removing:

$ kubectl exec redis-cluster-6 -- redis-cli cluster nodes | grep myself
27259a4ae75c616bbde2f8e8c6dfab2c173f2a1d 172.17.0.10:6379 myself,master - 0 0 9 connected 0-1364 5461-6826 10923-12287
Also note the id of any other master node:

$ kubectl exec redis-cluster-6 -- redis-cli cluster nodes | grep master | grep -v myself
32f250e02451352e561919674b8b705aef4dbdc6 172.17.0.4:6379 master - 0 1495120400893 2 connected 6827-10922
2a42aec405aca15ec94a2470eadf1fbdd18e56c9 172.17.0.6:6379 master - 0 1495120398342 8 connected 12288-16383
0990136c9a9d2e48ac7b36cfadcd9dbe657b2a72 172.17.0.2:6379 master - 0 1495120401395 1 connected 1365-5460
Then, use the reshard command to move all slots from redis-cluster-6:

kubectl exec redis-cluster-0 -- redis-cli --cluster reshard --cluster-yes \
--cluster-from 27259a4ae75c616bbde2f8e8c6dfab2c173f2a1d \
--cluster-to 32f250e02451352e561919674b8b705aef4dbdc6 \
--cluster-slots 16384 \
$(kubectl get pod redis-cluster-0 -o jsonpath='{.status.podIP}'):6379
After resharding, it is safe to delete the redis-cluster-6 master node:

kubectl exec redis-cluster-0 -- redis-cli --cluster del-node \
$(kubectl get pod redis-cluster-0 -o jsonpath='{.status.podIP}'):6379 \
27259a4ae75c616bbde2f8e8c6dfab2c173f2a1d
Finally, we can rebalance the remaining masters to evenly distribute slots:

kubectl exec redis-cluster-0 -- redis-cli --cluster rebalance --cluster-use-empty-masters \
$(kubectl get pod redis-cluster-0 -o jsonpath='{.status.podIP}'):6379
# Scaling down
After the master has been resharded and both nodes are removed from the cluster, it is safe to scale down the statefulset:

kubectl scale statefulset redis-cluster --replicas=6
# Cleaning up
kubectl delete statefulset,svc,configmap,pvc -l app=redis-cluster

# FIX
单节点 down掉再启动 可以自动恢复 redis cluster
如果是持久化nodes.conf dump.rdb, 关闭所有redis节点再重启, 这时集群恢复失败, nodes.conf ip信息为旧的信息, 由k8s pod ip变化引起, 且redis 配置不支持域名, 解决方法需人工介入, 修改某一持久化 nodes.conf, 更改相关IP 信息, 即可恢复集群
eg:
kubectl delete -f redis-cluster.yaml
kubectl create -f redis-cluster.yaml
state: cluster down
192.168.3.2 vim /opt/gfs_data/redis0/nodes/conf  ip info
kubectl delete po redis-cluster-0
kubectl exec -it redis-cluster-0 
redis-cli -c 
cluster state ok
finish



