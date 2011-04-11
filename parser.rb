require 'csv'
require 'active_support'
require 'active_support/inflector/transliterate.rb'
require 'ya2yaml'

class GeoNamesParser
  include ActiveSupport::Inflector
  COUNTRY_FIELDS  = %w(iso iso3 iso_numeric fips name capital area_sq_km population continent tld currency_code currency_name phone postal_code_format postal_code_regex languages geonamesid neighbours)
  REGION_FIELDS   = %w(fips_code name ascii_name geonamesid)
  CITY_FIELDS     = %w(geonamesid name ascii_name alternate_names latitude longitude feature_class feature_code country_code cc2 admin1_code admin2_code admin3_code admin4_code population elevation gtopo_30 timezone modification_date)

  def initialize opts = {}
    @country_fields   = opts.delete(:country_fields)  || COUNTRY_FIELDS + %w(regions localized_names)
    @region_fields    = opts.delete(:region_fields)   || REGION_FIELDS + %w(cities localized_names abbr)
    @city_fields      = opts.delete(:city_fields)     || CITY_FIELDS + %w(locales localized_names)
    @locales          = opts.delete(:locales)         || ['en']
    @alternate_names  = opts.delete(:alternate_names) || 3
    @alternate_names -= 1 
    @export_dir       = opts.delete(:export_dir)      || 'data'
  end

  def parse
    @countries, @regions, @cities, @localized_names = nil
    countries.map do |country|
      country['regions'] = extract_regions_for country['iso'] if @country_fields.include? 'regions'
      set_localized_names_for country if @country_fields.include? 'localized_names'

      cleanup_fields country, @country_fields
      country
    end
  end

  def export!
    parse.each do |country|
      path = File.join(@export_dir, "#{parameterize country['name']}.yml")
      File.open(path, "w+") { |f| f.write country.ya2yaml }
    end
  end

  private
  def countries
    @countries ||= parse_countries
  end

  def regions
    @regions ||= parse_regions
  end

  def cities
    @cities ||= parse_cities
  end

  def extract_regions_for country_code
    (regions_by_country_code[country_code] || []).map do |region|
      region['cities'] = extract_cities_for region['fips_code'] if @region_fields.include? 'cities'
      set_localized_names_for region if @region_fields.include? 'localized_names'

      cleanup_fields region, @region_fields
      region
    end
  end

  def extract_cities_for region_id
    (cities_by_fips_region[region_id] || []).map do |city|
      next if %w{PPLX PPLL PPLQ}.include? city['feature_code']
      set_localized_names_for city if @city_fields.include? 'localized_names'

      cleanup_fields city, @city_fields
      city
    end.compact
  end

  def regions_by_country_code
    @rbcc ||= regions.group_by{ |region| region['fips_code'].match(/^\w+/).to_s }
  end

  def cities_by_fips_region
    @cbi ||= cities.group_by { |city| "%s.%s" % [city['country_code'], city['admin1_code']] }
  end

  def parse_countries
    parse_csv('GeoNames Data/countryInfo.txt', COUNTRY_FIELDS) do |row| 
      split(row, 'neighbours')
      split(row, 'languages')
      row['area_sq_km'] = row['area_sq_km'].to_i
      row
    end
  end

  def parse_regions
    parse_csv('GeoNames Data/admin1CodesASCII.txt', REGION_FIELDS)
  end

  def parse_cities
    parse_csv('GeoNames Data/cities1000.txt', CITY_FIELDS) do |row| 
      split row, 'alternate_names', @alternate_names
      row['population'] = row['population'].to_i if row['population']
      row
    end
  end

  def localized_names
    @localized_names ||= parse_localized_names
  end

  def parse_localized_names
    names = {}
    File.open('GeoNames Data/alternateNames.txt').each do |row|
      id, geoid, locale, name = row.strip.split("\t")
      if @locales.include? locale
        names[geoid] ||= {}
        (names[geoid][locale] ||= []) << name
      end
    end
    names
  end

  def parse_csv file, headers
    collection = []
    File.open(file).each do |row|
      next if row.match(/^#/)
      row = Hash[*headers.zip(row.strip.split("\t").map{ |f| f.empty? ? nil : f }).flatten]
      collection.push(block_given? ? yield(row) : row) 
    end
    collection.compact!
    collection
  end

  def split hash, key, size = -1
    hash[key] = hash[key].split(',')[0..size] if hash[key] 
  end

  def set_localized_names_for entity
    geoid = entity['geonamesid']
    names = localized_names[geoid] || {}
    @locales.each { |locale| entity["names_#{locale}"] = names[locale] }
  end

  def cleanup_fields entity, fields
    entity.keep_if do |key, val|
      key.match(/^names_\w+$/) || fields.include?(key) 
    end
  end
end

parser = GeoNamesParser.new(:locales => %w(es en), :country_fields => %w(name regions localized_names), :region_fields => %(name cities localized_names ascii_name abbr), :city_fields => %(name alternate_names population localized_names ascii_name))
parser.export!


nil
