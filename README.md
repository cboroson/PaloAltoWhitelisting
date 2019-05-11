
# Palo Alto Whitelisting

Manage Palo Alto Global Protect client routing.

## Getting Started

I wrote this extension because Azure's integration with third party firewalls (e.g. Palo Alto) is challenging.  Specifically, we needed to restrict access to PaaS services by routing those services over the Global Protect VPN client.  This required the addition of Microsoft's PaaS service IP address ranges to our Palo Alto split-tunneling configuration.  The list of Azure IP ranges is very large and it changes.  Keeping up with the changes through automation led to this extension.

### Prerequisites
This extension requires an existing Palo Alto firewall configured for Global Protect clients.

## Configuration
Enter the Palo hostname, username and password.  Select the regions and services to include in the whitelist configuration.

## Contributing

Please read [CONTRIBUTING.md](https://gist.github.com/PurpleBooth/b24679402957c63ec426) for details on our code of conduct, and the process for submitting pull requests to us.

## Versioning

We use [SemVer](http://semver.org/) for versioning. For the versions available, see the [tags on this repository](https://github.com/your/project/tags). 

## Authors

* Craig Boroson 

See also the list of [contributors](https://github.com/cboroson/PaloAltoWhitelisting/contributors) who participated in this project.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details

