echo "= Disk usage before ="
docker system df
echo

dokcer container prune -f
docker network prune -f
docker builder prune -f

echo
echo "= Disk usage after ="
docker system df
