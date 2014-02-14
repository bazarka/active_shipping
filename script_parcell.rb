require 'active_shipping'
destination = ActiveMerchant::Shipping::Location.new(country: 'US', state: 'CA', city: 'Beverly Hills', zip: '90210', address1: 'Wojska Polskiego', phone: '0014142416256', company: 'WebWizard')
origin = ActiveMerchant::Shipping::Location.new(country: 'US', state: 'CA', city: 'Beverly Hills', zip: '90210', address1: 'Wojska Polskiego', phone: '0014142416256', company: 'WebWizard')
package1 = ActiveMerchant::Shipping::Package.new(100, [93, 10], cylinder: true)
packages = []
packages << package1
w = ActiveMerchant::Shipping::SmallParcel.new(loginId: 'scoutnimble', password: 'worldwide', licenseKey: 'pg3fg8fpSZf5BPwC', accountNumber: 'W403499889')
response = w.find_rates(origin, destination, packages, {dupa: 'dupa'})
