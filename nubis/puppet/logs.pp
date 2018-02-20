fluentd::configfile { $project_name: }

fluentd::source { 'node-output':
  configfile  => $project_name,
  type        => 'tail',
  format      => 'none',
  time_format => '%Y-%m-%dT%H:%M:%S.%L%Z',

  tag         => 'forward.voice.node.stdout',
  config      => {
    'read_from_head' => true,
    'path'           => "/var/log/vertical-startup.log",
    'pos_file'       => "/var/log/vertical-startup.pos",
  },
}
