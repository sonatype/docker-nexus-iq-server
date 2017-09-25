# spec/Dockerfile_spec.rb

require "serverspec"
require "docker"

describe "Dockerfile" do
  before(:all) do
    Docker.options[:read_timeout] = 900
    @image = Docker::Image.build_from_dir('.')

    set :os, family: :redhat
    set :backend, :docker
    set :docker_image, @image.id
  end

  it "should generate a valid solo.json file" do
    solo = JSON.parse(File.read('/var/chef/solo.json'))
    expect(solo['run_list']).to eq([ 'recipe[nexus-iq-server::docker]' ])
  end

  it "should not have a chef package installed" do
    expect(package("chef")).not_to be_installed
  end

  it "should have a user named nexus" do
    expect(user('nexus')).to exist
  end

  it "should have a nexus java process running" do
    expect(process('java')).to be_running
    expect(process('java')).to have_attributes(:user => 'nexus')
  end
end
