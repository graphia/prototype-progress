require "nokogiri"
require "open-uri"
require "set"
require "pry"
require "graphviz"
require "selenium-webdriver"

class Crawler
  ENTRY_POINT = "/".freeze
  attr_accessor :pages

  def initialize
    initial_page = Page.new(ENTRY_POINT)
    self.pages = { "/" => initial_page }
    crawl(initial_page)
  end

  def crawl(current_page)
    current_page
      .links_to
      .reject { |href| pages.keys.include?(href) }
      .each do |href|
        Page.new(href).tap do |page|
          pages[href] = page
          crawl(page)
        end
      end
  end

  def links_graph
    pages
      .values
      .each_with_object({}) { |p, o| o[p.path] = p.links_to }
  end
end

class Page
  PORT = 3001

  attr_reader :path, :body

  def initialize(path)
    puts "Parsing #{path}"
    @path = path
    @body = read
  end

  def links_to
    body
      .css("a.govuk-button")
      .map { |link| link["href"] }
  end

  def uri
    File.join("http://localhost:#{PORT}", path)
  end

private

  def read
    Nokogiri::HTML.parse(OpenURI.open_uri(uri))
  end
end


options = Selenium::WebDriver::Firefox::Options.new(args: ["-headless"])
driver = Selenium::WebDriver.for(:firefox, options: options)
window_size = OpenStruct.new(width: 800, height: 600)
driver.manage.window.size = window_size

crawler = Crawler.new

crawler.pages.values.each.with_index do |page, i|
  driver.get(page.uri)


  width  = driver.execute_script("return Math.max(document.body.scrollWidth, document.body.offsetWidth, document.documentElement.clientWidth, document.documentElement.scrollWidth, document.documentElement.offsetWidth);")
  height = driver.execute_script("return Math.max(document.body.scrollHeight, document.body.offsetHeight, document.documentElement.clientHeight, document.documentElement.scrollHeight, document.documentElement.offsetHeight);")

  driver.manage.window.resize_to(width + 100, height)

  puts driver.title

  driver.save_screenshot("tmp/#{i}.png")
end


graph = Graphviz::Graph.new(rankdir: "LR", ranksep: 3).tap do |g|
  crawler.links_graph.each.with_index do |(path, _), i|
    g.add_node(path, shape: "box", imagescale: true, image: "tmp/#{i}.png")
  end

  crawler.links_graph.each do |path, links|
    links.each { |link| g.nodes[path].connect(g.nodes[link], arrowsize: 2, penwidth: 7) }
  end
end

puts graph.to_dot

Graphviz::output(graph, path: "test.png", format: "png")

driver.quit
