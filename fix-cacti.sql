
CREATE TABLE `host_errors` (
  `host_id` mediumint(8) unsigned NOT NULL default 0,
  `poller_id` int(10) unsigned NOT NULL default 1,
  `errors` mediumint(8) unsigned NOT NULL default 0,
  `local_data_ids` text default NULL,
  PRIMARY KEY (`host_id`),
  KEY `poller_id` (`poller_id`)
) ENGINE=InnoDB ROW_FORMAT=DYNAMIC COMMENT='Holds Device Error buffer for Spine';

