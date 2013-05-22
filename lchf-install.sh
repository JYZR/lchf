# Jimmy's public key
echo "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA07PIQff/yMXSccMsf4GBDo2O1pRcN0Q8+jZ+K3mHB4RvmUlfSMzdxFNCdTj4Wigq+QMMaFCa+YlpYQQx4qBhgucpI8PvBrzDBC1RjV9AR2kaMfZteg3LRYCcLU5HLX0MeNndm08bSagIqH/Kc532VDUmZmFOIvLDyJWYckc6sO7IUD3bUsRiXAic0iu8uu0kZORiRdq12T8nLWdIRvxgSNJSt7XcqLPSfsOuHRid9X5DHI7GjySNDYt72xwzzb0aZbH4S61deWNL3B6RWjVYKaD2IYkkzNeDG9B2FVgfMTOi35ULO9YVpH7rRdMET0nleMlHoRu/gDAg8tsbv/hyXw== jimmy.zoger@gmail.com" >> ~/.ssh/authorized_keys

# Roshan's public key
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC4PAyVV7lS6su6Gr50ALenBclQqb4sw9wXBt4sv1gwh087iwU5id4oJS++St1BEub0cPLHo6Nu/FtLzv+6h81vLZrp7k0H/vvHm0sqxN++d55IaQydc/bLMngj4UE4b1TtsCS3spnG565DbCqD8sCZFRAARBoliJHZAbG3Ebrr8544OwOT9uHQw8LyXonYKB09yEVbGpR9BhqzNYQAFOQpZZbLxE4fEP5/ydSiqsxL/45i2eLzLCXdd4KaXkw0+otHTCGEjxZD+2ZQJlmlTZi2EOKSTq+cpLGFpdPA8JeIUbEDlBaEzRaumkoeFIJB7NjHnjdQYgynSoo3/w7bokcfUU4x+T13C9arK49gXvqomCQX0k5po5ICl/KGlsXsKCKa+JsHtQwh3kKLaQDo/VcxAVoOw6zwEfkw5FO1V3ihcM+OibhiyCcTMp/pJ+8r1L9KlGjwYNhBSSQQdQXZevqdhsrD40AyCVZdwXjRF0ovBp+N0/cy/M0XXk0P/jPX+GawaXO6MU5qHGl7jQq+o8xz42OPHw9d4lqhjhlMcQe3crY5GBscErBzwyHviwFo0+sfde9ytgEAjJN2ASJOWR3FMXZwIL2+Zvrj/TvclEusRexr46Hhe1YkkDzW4ekLEN1wJ3TI3XRFDlKtFZMf4BokV0OeX8FCaajKIhxNhXimeQ== roshan@roshan-se" >> ~/.ssh/authorized_keys

# Alé's public key
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDUGijxoaXkPmfKWsWuC6O0XmPmn06wlqYdnZ9oqCYRbTclLp7zfDlbKFw1YUw/8pd2sVaINK4Ws4xhfLRZm73yDcW1J7V2tVCHvqZOxLqCB1jjhODXvwHrsqIVk77vNJYQK1H+vu1dVnjkY6+GNTroqp9wGR3iY50I1xuPQslbM0HxI53/if3uvY3TtEJskIEs+6x3Uq9TMQcg/tA0XDEznb7Wqd6JlwVAE7SGjztdFfSldulE5537wQFb+5yzrMwBIZURHSAjZOu8cQgR5K5E7yQuXxGJLq0gijYtavrdOYMpv/fSF5WyEfzrrF8LMpLqynPlySIu5pmDZ4hiSMC/ aecc@AeccLaptop" >> ~/.ssh/authorized_keys

sudo yum update

# Cassandra can not run with OpenJDK, it results in segmentation fault
# We better install Oracle JAVA
wget --no-cookies --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2Ftechnetwork%2Fjava%2Fjavase%2Fdownloads%2Fjdk-7u3-download-1501626.html;" http://download.oracle.com/otn-pub/java/jdk/7u21-b11/jdk-7u21-linux-x64.rpm
sudo rpm -i jdk-7u21-linux-x64.rpm
sudo /usr/sbin/alternatives --install /usr/bin/java java /usr/java/jdk1.7.0_21/bin/java 20000
sudo rm /etc/alternatives/java 
sudo ln /usr/java/jdk1.7.0_21/bin/java /etc/alternatives/java --symbolic

# Download Cassandra
wget http://apache.rediris.es/cassandra/1.2.4/apache-cassandra-1.2.4-bin.tar.gz

tar xvf apache-cassandra-1.2.4-bin.tar.gz

# Before starting Cassandra we need to have an updated configuration file
# apache-cassandra-1.2.4/conf/cassandra.yaml
# with the IP addresses of the nodes

cp lchf-cassandra.yaml apache-cassandra-1.2.4/conf/cassandra.yaml

sudo mkdir -p /var/lib/cassandra/data
sudo mkdir -p /var/lib/cassandra/commitlog
sudo mkdir -p /var/lib/cassandra/saved_caches
sudo mkdir -p /var/log/cassandra

sudo chown -R ec2-user:ec2-user /var/lib/cassandra/
sudo chown -R ec2-user:ec2-user /var/log/cassandra/

export PATH=$PATH:~/apache-cassandra-1.2.4/bin/
echo "export PATH=$PATH:~/apache-cassandra-1.2.4/bin/" >> .bash_profile

# Start cassandra
# ~/apache-cassandra-1.2.4/bin/cassandra >> lchf-cassandra-start-log

# Install Python with cql and flask
sudo yum install -y python-pip
sudo chown ec2-user /usr/lib/python2.6/site-packages/
sudo ln /usr/bin/python-pip /usr/bin/pip --symbolic
pip install flask
pip install cql
mkdir -p ~/api
cp ~/zocial.py ~/api/zocial.py
python ~/api/zocial.py &
