require 'yaml'
require 'net/ssh'
require 'net/scp'

YAML.load(File.open("lchf-instances.yaml")).each do |instance_info|
	Net::SSH.start(instance_info['dns_name'], "ec2-user") do |ssh|
      puts "Updating zocial.py on " + instance_info['dns_name']
      ssh.scp.upload! "../api/zocial.py", "api/zocial.py"
    end
end

	