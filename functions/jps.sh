function jps()
{
	ps -ef | grep $1 | grep -v grep | grep $1
}
function jpsi()
{
	ps -ef | grep -i $1 | grep -v grep | grep -i $1
}
