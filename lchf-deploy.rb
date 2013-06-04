# Launch Cassandra, Hadoop & Flask #
# ------------- lchf ------------- #

# ruby lchf-deploy.rb lchf-conf.yaml
# Creates instances on AWS

# First, set your credentials as environment variabless
# export AWS_ACCESS_KEY_ID=
# export AWS_SECRET_ACCESS_KEY=

# Also upload public key to all regions through the AWS console

# If this is the first time, also make sure to run LCHF::create_security_group_in_each_region

require './lchf'

################################################################################

options = {}

options[:configuration_filename] = ARGV[0] if ARGV[0]
puts "Configuration file: #{options[:configuration_filename]}" if ARGV[0]

options[:instances_filename] = ARGV[1] if ARGV[1]
puts "instances file: #{options[:instances_filename]}" if ARGV[1]

LCHF.deploy options
LCHF.generate
