require 'sinatra'
require 'sinatra/reloader'
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

configure do
  enable :sessions
  # set :session_secret, 'something'
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_contents(path)
  content = File.read(path)

  case File.extname path
  when '.txt'
    headers['Content-Type'] = 'text/plain'
    content
  when '.md'
    render_markdown(content)
  end
end

def load_user_credentials
  credentials_path = if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/users.yml', __FILE__)
  else
    File.expand_path('../users.yml', __FILE__)
  end

  YAML.load_file(credentials_path)
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data', __FILE__)
  else
    File.expand_path('../data', __FILE__)
  end
end

def create_document(name, content = "")
  File.open(File.join(data_path, name), 'w') do |file|
    file.write(content)
  end
end

def credentials_valid?(username, password)
  stored_credentials = load_user_credentials
  crypt_password = BCrypt::Password.new(stored_credentials[username])
  stored_credentials.key?(username) && crypt_password == password
end

def signed_in?
  session.key?(:user)
end

def confirm_signed_in
  unless signed_in?
    session['message'] = 'You must be signed in to complete the action.'
    redirect '/'
  end
end

get '/' do
  if signed_in?
    @files = Dir["#{data_path}/*"].map { |file_path| File.basename(file_path) }.sort
    erb :files, layout: :layout
  else
    redirect '/users/signin'
  end
end

get '/new' do
  confirm_signed_in

  erb :new, layout: :layout
end

get '/:file_name' do |file_name|
  file_path = "#{data_path}/#{file_name}"
  if (File.exist?(file_path))
    load_file_contents(file_path)
  else
    session[:message] = "#{file_name} does not exist."
    redirect '/'
  end
end

get '/:file_name/edit' do |file_name|
  confirm_signed_in

  file_path = "#{data_path}/#{file_name}"
  @file_name = file_name
  @file_contents = File.read(file_path)
  erb :edit, layout: :layout
end

post '/:file_name' do |file_name|
  confirm_signed_in

  file_path = "#{data_path}/#{file_name}"
  file = File.new(file_path, 'w')
  file.write(params[:edit_text])
  file.close
  session[:message] = "#{file_name} has been updated."
  redirect '/'
end

post '/' do
  confirm_signed_in

  new_doc = params[:new_doc]

  if new_doc.empty?
    session[:message] = 'A name is required.'
    status 422
    erb :new, layout: :layout
  else
    create_document(new_doc)
    session[:message] = "#{new_doc} has been created"
    redirect '/'
  end
end

post '/:file_name/delete' do |file_name|
  confirm_signed_in

  FileUtils.rm(File.join(data_path, file_name))
  session[:message] = "#{file_name} has been deleted."
  redirect '/'
end

get '/users/signin' do

  erb :signin, layout: :layout
end

post '/users/signin' do
  username = params[:username]
  password = params[:password]

  if credentials_valid?(username, password)
    session[:user] = username
    session[:message] = 'Welcome!'
    redirect '/'
  else
    session[:message] = 'Invalid credentials'
    status 422
    erb :signin, layout: :layout
  end
end

post '/users/signout' do
  session.delete(:user)
  session[:message] = 'You have been signed out'
  redirect '/'
end


