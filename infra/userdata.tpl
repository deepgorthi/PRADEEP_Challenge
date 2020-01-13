#!/bin/bash
yum install httpd -y
echo "<html> \
<head> \
<title>Hello World</title> \
</head> \
<body> \
<h1>Hello World!</h1> \
</body> \
</html>" >> /var/www/html/index.html
service httpd start
chkconfig httpd on