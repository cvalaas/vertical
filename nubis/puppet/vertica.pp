# Required Packages
package { 'sysstat':
  ensure => 'latest',
}

package { 'mcelog':
  ensure => 'latest',
}

package { 'gdb':
  ensure => 'latest',
}

package { 'unzip':
  ensure => 'latest',
}

package { 'nmap':
  ensure => 'latest',
}

package { 'dialog':
  ensure => 'latest',
}

package { 'moreutils':
  ensure => 'latest',
}

python::pip { 'awscli':
  ensure  => 'latest',
}

# System tuning

sysctl { 'vm.swappiness':
  value => '1'
}

file { "/etc/nubis.d/00-${project_name}":
  ensure => file,
  owner  => root,
  group  => root,
  mode   => '0755',
  source => 'puppet:///nubis/files/startup',
}

file { '/usr/local/bin/vertical-bootstrap':
  ensure => file,
  owner  => root,
  group  => root,
  mode   => '0755',
  source => 'puppet:///nubis/files/bootstrap',
}

file { '/home/dbadmin/schema.sql':
  ensure => file,
  owner  => root,
  group  => root,
  mode   => '0644',
  source => 'puppet:///nubis/files/schema.sql',
}

include nubis_discovery

# Switch to MC port once working
nubis::discovery::service { $project_name:
  tcp      => '5433',
}

nubis::discovery::service { "${project_name}-console":
  tcp  => '5450',
  tags => [
    'sso=true',
    'ssl-ssl=true',
    'environment=%%ENVIRONMENT%%',
  ],
}

file { "/etc/sudoers.d/${project_name}":
  ensure  => file,
  owner   => 'root',
  group   => 'root',
  mode    => '0644',
  content => 'dbadmin ALL=(ALL) NOPASSWD:ALL',
}


# Run the management console on a single node ever

$console_command = "consul-do ${project_name}-console $(hostname) && /etc/init.d/vertica-consoled start || /etc/init.d/vertica-consoled stop"

# Run it once on boot
cron { "${project_name}-console-onboot":
  command => $console_command,
  user    => 'root',
  special => 'reboot',
}

cron { "${project_name}-console-watchdog":
  command => $console_command,
  user    => 'root',
  minute  => '*/5',
}

cron { "${project_name}-read-scaledown-queue":
  command => '$HOME/autoscale/read_scaledown_queue.sh',
  user    => 'dbadmin',
  minute  => '*',
}

cron { "${project_name}-down-node-check":
  command => '$HOME/autoscale/down_node_check.sh',
  user    => 'dbadmin',
  minute  => '*',
}

# Daily Backups
cron::daily { "${project_name}-backup":
  command => 'consul-do "$(nubis-metadata NUBIS_PROJECT)-$(nubis-metadata NUBIS_ENVIRONMENT)" "$(hostname)" && su - dbadmin -c "nubis-cron /opt/vertica/bin/vbr --task backup -c /etc/vertica-backup.conf --debug 3" >> /var/log/vertica-backup.log 2>&1 || true',
  user    => 'root',
}
