require 'active_shipping'
destination = ActiveMerchant::Shipping::Location.new(country: 'US', state: 'CA', city: 'Beverly Hills', zip: '90210', address1: 'Wojska Polskiego', phone: '0014142416256', company: 'WebWizard')
origin = ActiveMerchant::Shipping::Location.new(country: 'US', state: 'CA', city: 'Beverly Hills', zip: '90210', address1: 'Wojska Polskiego', phone: '0014142416256', company: 'WebWizard')
w = {'line1' => {'class_type' => 50, 'weight' => 4, 'description' => 'desc', 'piece_type' => 'TBE', 'number_pieces' => 4}, 'line2' => {'class_type' => 55, 'weight' => 4, 'description' => 'desc', 'piece_type' => 'BAL', 'number_pieces' => 4}}
package1 = ActiveMerchant::Shipping::Package.new(100, [93, 10], cylinder: true)
package1.options['units'] = 'Pallet'
package1.options['number'] = 2
package1.options['lines'] = w
packages = []
packages << package1
w = ActiveMerchant::Shipping::LTL.new(loginId: 'scoutnimble', password: 'worldwide', licenseKey: 'pg3fg8fpSZf5BPwC', accountNumber: 'W403499889')
response = w.find_rates(origin, destination, packages, {dupa: 'dupa'})
options = {'shipment_date' => '02/16/2014', 'shipment_ready_time' => '08:00 am', 'shipment_closing_time' => '09:00 pm'}
rates_response =  response.rates.first
table = []
book = w.book_shipment(origin, destination , rates_response, options)
book1 = w.book_shipment(origin, destination , rates_response, options)
table << book[:number]
table << book1[:number]
#void = w.void_shipment(table)
pro = w.pro_number(table)

puts pro




