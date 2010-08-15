output=`$@ 2>&1`
if (( $? )); 
then 
	result='bad';
else 
	result='good';
fi
command=$(echo -n $@ | perl -pe's/([^-_.~A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg');
output=$(echo -n $output | perl -pe's/([^-_.~A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg');
curl 'http://anyan.org/script/prowl/send.php?app=bash&event='+$command+'&priority=1&pass=josh123&desc='+$result+':'+$output
