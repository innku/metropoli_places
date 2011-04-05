require 'json'
require 'ya2yaml'
require 'yaml'
require 'active_support'
require 'carmen'
require 'active_support/inflector/transliterate'

class CityParser
  include ActiveSupport::Inflector

  def initialize json
    @raw       = JSON.parse json
    @countries = @raw.select { |m| m['model'] == 'cities.country' }
    @regions   = @raw.select { |m| m['model'] == 'cities.region' }
    @cities    = @raw.select { |m| m['model'] == 'cities.city' }
    @districts = @raw.select { |m| m['model'] == 'cities.district' }
  end

  def extract
    @countries.map do |country|
      country['fields'].merge 'regions' => extract_regions_for_country(country)
    end
  end

  def make_yamls!
    extract.each do |country|
      File.open("data/#{parameterize country['name']}.yml", "w+") { |f| f.write country.ya2yaml }
    end
  end

  def extract_regions_for_country country
    abbrs = Carmen.states country['fields']['code'] rescue nil
    regions_by_country[country['pk']].map do |region|
      fields = region['fields'].dup
      fields.delete 'country'
      abbr = abbrs.assoc(fields['name']) if abbrs
      fields.merge!('abbr' => abbr.last) if abbr
      fields.merge 'cities' => extract_cities_for_region(region)
    end
  end

  def extract_cities_for_region region
    cities_by_region[region['pk']].map do |city|
      fields = city['fields'].dup
      fields.delete 'region'
      fields.merge 'districts' => extract_districts_for_city(city)
    end
  end

  def extract_districts_for_city city
    return [] unless districts = districts_by_city[city['pk']]
    districts.map do |district| 
      fields = district['fields'].dup
      fields.delete 'city'
      fields
    end
  end

  def regions_by_country
    @rbc ||= @regions.group_by{ |region| region['fields']['country'] }
  end

  def cities_by_region
    @cbr ||= @cities.group_by{ |city| city['fields']['region'] }
  end

  def districts_by_city
    @dbc ||= @districts.group_by{ |district| district['fields']['city'] }
  end
end

json = File.read('cities.json') # from django_cities library: https://github.com/coderholic/django-cities
CityParser.new(json).make_yamls!
