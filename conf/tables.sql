-- 2010-06-25

-- For: CWL
-- TABLE: cwl_domains (SQLITE):
CREATE TABLE CWL_DOMAINS (sender_domain varchar(255), recipient_domain varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX CWL_DOMAINS_RECIPIENT_DOMAIN_SENDER_DOMAIN ON CWL_DOMAINS (recipient_domain, sender_domain);

-- TABLE: cwl_addresses (SQLITE):
CREATE TABLE CWL_ADDRESSES (sender_address varchar(255), recipient_domain varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX CWL_ADDRESSES_RECIPIENT_DOMAIN_SENDER_ADDRESS ON CWL_ADDRESSES (recipient_domain, sender_address);

-- TABLE: cwl_ips (SQLITE):
CREATE TABLE CWL_IPS (client_address varchar(39), recipient_domain varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX CWL_IPS_RECIPIENT_DOMAIN_CLIENT_ADDRESS ON CWL_IPS (recipient_domain, client_address);


-- For: CBL
-- TABLE: cbl_domains (SQLITE):
CREATE TABLE CBL_DOMAINS (sender_domain varchar(255), recipient_domain varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX CBL_DOMAINS_RECIPIENT_DOMAIN_SENDER_DOMAIN ON CBL_DOMAINS (recipient_domain, sender_domain);

-- TABLE: cbl_addresses (SQLITE):
CREATE TABLE CBL_ADDRESSES (sender_address varchar(255), recipient_domain varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX CBL_ADDRESSES_RECIPIENT_DOMAIN_SENDER_ADDRESS ON CBL_ADDRESSES (recipient_domain, sender_address);

-- TABLE: cbl_ips (SQLITE):
CREATE TABLE CBL_IPS (client_address varchar(39), recipient_domain varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX CBL_IPS_RECIPIENT_DOMAIN_CLIENT_ADDRESS ON CBL_IPS (recipient_domain, client_address);


-- For: GeoWeight
-- TABLE: geo_stats (SQLITE):
CREATE TABLE GEO_STATS (country varchar(2), counter integer, interval varchar(25), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX GEO_STATS_COUNTRY_INTERVAL ON GEO_STATS (country, interval);


-- For: Honeypot
-- TABLE: honeypot_addresses (SQLITE):
CREATE TABLE HONEYPOT_ADDRESSES (created integer, client_address varchar(39), id INTEGER PRIMARY KEY);
CREATE INDEX HONEYPOT_ADDRESSES_CREATED ON HONEYPOT_ADDRESSES (created);
CREATE UNIQUE INDEX HONEYPOT_ADDRESSES_CLIENT_ADDRESS ON HONEYPOT_ADDRESSES (client_address);


-- For: Greylist
-- TABLE: greylist_sender_recipient (SQLITE):
CREATE TABLE GREYLIST_SENDER_RECIPIENT (sender_address varchar(255), max_unique integer, unique_sender blob, last_seen integer, counter integer, max_one integer, recipient_address varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX GREYLIST_SENDER_RECIPIENT_SENDER_ADDRESS_RECIPIENT_ADDRESS ON GREYLIST_SENDER_RECIPIENT (sender_address, recipient_address);

-- TABLE: greylist_sender_domain (SQLITE):
CREATE TABLE GREYLIST_SENDER_DOMAIN (max_unique integer, unique_sender blob, sender_domain varchar(255), last_seen integer, counter integer, max_one integer, id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX GREYLIST_SENDER_DOMAIN_SENDER_DOMAIN ON GREYLIST_SENDER_DOMAIN (sender_domain);

-- TABLE: greylist_client_address (SQLITE):
CREATE TABLE GREYLIST_CLIENT_ADDRESS (last_seen integer, counter integer, client_address varchar(39), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX GREYLIST_CLIENT_ADDRESS_CLIENT_ADDRESS ON GREYLIST_CLIENT_ADDRESS (client_address);


-- For: Throttle
-- TABLE: throttle_sender_address (SQLITE):
CREATE TABLE THROTTLE_SENDER_ADDRESS (sender_address varchar(255), maximum integer, account varchar(100), interval integer, id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX THROTTLE_SENDER_ADDRESS_SENDER_ADDRESS_INTERVAL ON THROTTLE_SENDER_ADDRESS (sender_address, interval);

-- TABLE: throttle_sasl_username (SQLITE):
CREATE TABLE THROTTLE_SASL_USERNAME (maximum integer, sasl_username varchar(255), account varchar(100), interval integer, id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX THROTTLE_SASL_USERNAME_SASL_USERNAME_INTERVAL ON THROTTLE_SASL_USERNAME (sasl_username, interval);

-- TABLE: throttle_account (SQLITE):
CREATE TABLE THROTTLE_ACCOUNT (maximum integer, account varchar(100), interval integer, id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX THROTTLE_ACCOUNT_ACCOUNT_INTERVAL ON THROTTLE_ACCOUNT (account, interval);

-- TABLE: throttle_sender_domain (SQLITE):
CREATE TABLE THROTTLE_SENDER_DOMAIN (maximum integer, account varchar(100), sender_domain varchar(255), interval integer, id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX THROTTLE_SENDER_DOMAIN_SENDER_DOMAIN_INTERVAL ON THROTTLE_SENDER_DOMAIN (sender_domain, interval);

-- TABLE: throttle_client_address (SQLITE):
CREATE TABLE THROTTLE_CLIENT_ADDRESS (maximum integer, account varchar(100), client_address varchar(39), interval integer, id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX THROTTLE_CLIENT_ADDRESS_CLIENT_ADDRESS_INTERVAL ON THROTTLE_CLIENT_ADDRESS (client_address, interval);

-- TABLE: throttle_recipient_domain (SQLITE):
CREATE TABLE THROTTLE_RECIPIENT_DOMAIN (maximum integer, account varchar(100), interval integer, recipient_domain varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX THROTTLE_RECIPIENT_DOMAIN_RECIPIENT_DOMAIN_INTERVAL ON THROTTLE_RECIPIENT_DOMAIN (recipient_domain, interval);

-- TABLE: throttle_recipient_address (SQLITE):
CREATE TABLE THROTTLE_RECIPIENT_ADDRESS (maximum integer, account varchar(100), interval integer, recipient_address varchar(255), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX THROTTLE_RECIPIENT_ADDRESS_RECIPIENT_ADDRESS_INTERVAL ON THROTTLE_RECIPIENT_ADDRESS (recipient_address, interval);


-- For: Mail::Decency::Doorman=HASH(0x2ad2be0)
-- TABLE: stats_doorman_response (SQLITE):
CREATE TABLE STATS_DOORMAN_RESPONSE (period varchar(10), type varchar(32), start integer, module varchar(32), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX STATS_DOORMAN_RESPONSE_MODULE_PERIOD_START_TYPE ON STATS_DOORMAN_RESPONSE (module, period, start, type);

-- TABLE: stats_doorman_performance (SQLITE):
CREATE TABLE STATS_DOORMAN_PERFORMANCE (calls varchar(10), runtime real, period varchar(10), type varchar(32), start integer, module varchar(32), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX STATS_DOORMAN_PERFORMANCE_MODULE_PERIOD_START_TYPE ON STATS_DOORMAN_PERFORMANCE (module, period, start, type);


-- TABLE: stats_detective_performance (SQLITE):
CREATE TABLE STATS_DETECTIVE_PERFORMANCE (calls varchar(10), runtime real, period varchar(10), type varchar(32), start integer, module varchar(32), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX STATS_DETECTIVE_PERFORMANCE_MODULE_PERIOD_START_TYPE ON STATS_DETECTIVE_PERFORMANCE (module, period, start, type);

-- TABLE: stats_DETECTIVE_response (SQLITE):
CREATE TABLE STATS_DETECTIVE_RESPONSE (period varchar(10), type varchar(32), start integer, module varchar(32), id INTEGER PRIMARY KEY);
CREATE UNIQUE INDEX STATS_DETECTIVE_RESPONSE_MODULE_PERIOD_START_TYPE ON STATS_DETECTIVE_RESPONSE (module, period, start, type);


