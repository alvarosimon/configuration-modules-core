object template wsgi_conf;

include 'metaconfig/httpd/schema';

bind "/software/components/metaconfig/services/{/etc/httpd/conf.d/wsgi.conf}/contents" = httpd_vhosts;

prefix "/software/components/metaconfig/services/{/etc/httpd/conf.d/wsgi.conf}";
"module" = "httpd/2.4/generic_server";
"daemons/httpd" = "restart";

variable FULL_HOSTNAME = 'myhost.domain';
variable HOSTNAME = 'myhost';
variable DB_IP = dict(HOSTNAME, '1.2.3.4');

prefix "/software/components/metaconfig/services/{/etc/httpd/conf.d/wsgi.conf}/contents/vhosts";

"django" = create("struct/default_vhost");
"django/directories" = {
    l = dict(
        "name", "/var/www/django/static",
        "ssl", dict("requiressl", true),
        "authz", list(
            dict(
                "negate", true,
                "ip", list("1.2.3.4"),
                "all", "granted",
            ),
            dict(
                "ip", list("my.hostname.domain", "4.5.6.7"),
                "expr", "some valid expression",
                "env", list("VARX", "VARY"),
                "user", list("user1", "user2"),
                "group", list("group1", "group2"),
                "all", "denied",
                "valid-user", "no reason",
                "method", list("m1", "m2"),
            ),
        ),
    );
    append(l);
};

prefix "/software/components/metaconfig/services/{/etc/httpd/conf.d/wsgi.conf}/contents/vhosts/django";

"aliases/0/url" = "/django/static/";
"aliases/0/destination" =  "/var/www/django/static/";
"aliases/1/url" = "/django";
"aliases/1/destination" = "/var/www/django/wsgi.py";
"aliases/1/type" = "wsgiscript";
"wsgi/passauthorization" = "on";

# can only be set in systemwide setting
prefix "/software/components/metaconfig/services/{/etc/httpd/conf.d/wsgi.conf}/contents/global";
"wsgipythonpath" = "/var/www/django";
