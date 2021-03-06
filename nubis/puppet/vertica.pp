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

service { 'tuned':
  ensure => 'stopped',
  enable => false,
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

file { "/etc/sudoers.d/${project_name}":
  ensure  => file,
  owner   => 'root',
  group   => 'root',
  mode    => '0644',
  content => 'dbadmin ALL=(ALL) NOPASSWD:ALL',
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
file { "/usr/local/bin/nubis-${project_name}-backup":
  ensure => file,
  owner  => root,
  group  => root,
  mode   => '0755',
  source => 'puppet:///nubis/files/backup',
}

cron::daily { "${project_name}-backup":
  command => "nubis-cron ${project_name}-backup /usr/local/bin/nubis-${project_name}-backup backup",
  user    => 'root',
}
