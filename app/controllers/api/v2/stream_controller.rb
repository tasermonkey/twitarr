class API::V2::StreamController < ApplicationController
  # noinspection RailsParamDefResolve
  skip_before_action :verify_authenticity_token

  PAGE_LENGTH = 20
  before_filter :login_required
  before_filter :fetch_post, :except => [:index, :create, :view_mention, :view_hash_tag]

  def login_required
    head :unauthorized unless logged_in?
  end

  def fetch_post
    begin
      @post = StreamPost.find(params[:id])
    rescue Mongoid::Errors::DocumentNotFound
      render status:404, json:{status:'Not found', id:params[:id], error: "Post by id #{params[:id]} is not found."}
    end
  end

  def index
    posts = nil
    if want_newest_posts?
      posts = newest_posts
    elsif want_older_posts?
      posts = older_posts
    elsif want_newer_posts?
      posts = newer_posts
    end
    render_json posts
  end

  def show
    render_json @post.decorate.to_hash
  end

  def view_mention
    query_string = params[:query]
    start_loc = params[:page] || 0
    limit = params[:limit] || PAGE_LENGTH
    query = StreamPost.or({mentions: query_string}, {author: query_string}).order_by(timestamp: :desc).skip(start_loc*limit).limit(limit)
    render status: :ok, json: {status: 'ok', posts: query.map { |x| x.decorate.to_hash }, next:(start_loc+limit)}
  end

  def view_hash_tag
    query_string = params[:query]
    start_loc = params[:page] || 0
    limit = params[:limit] || PAGE_LENGTH
    query = StreamPost.where(hash_tags: query_string).order_by(timestamp: :desc).skip(start_loc*limit).limit(limit)
    render status: :ok, json: {status: 'ok', posts: query.map { |x| x.decorate.to_hash }, next:(start_loc+limit)}

  end

  def destroy
    unless @post.author == current_username or is_admin?
      err = [{error:"You can not delete other users' posts"}]
      return respond_to do |format|
        format.json { render json: err, status: :forbidden }
        format.xml { render xml: err, status: :forbidden }
      end
    end
    respond_to do |format|
      if @post.destroy
        format.json { head :no_content, status: :ok }
        format.xml { head :no_content, status: :ok }
      else
        format.json { render json: @post.errors, status: :unprocessable_entity }
        format.xml { render xml: @post.errors, status: :unprocessable_entity }
      end
    end
  end

  def create
    post = StreamPost.create(text: params[:text], author: current_username, timestamp: Time.now, photo: params[:photo])
    if post.valid?
      render_json stream_post: post.decorate.to_hash
    else
      render_json status: :unprocessable_entity, errors: post.errors.full_messages
    end
  end

  # noinspection RubyResolve
  def update
    unless (params[:stream].keys - %w(text photo)).empty?
      render json:[{error:'Unable to modify fields other than text or photo'}], status: :bad_request
      return
    end

    unless @post.author == current_username or is_admin?
      err = [{error:"You can not modify other users' posts"}]
      render json: err, status: :forbidden
      return
    end
    @post.text = params[:text] if params.has_key? :text

    if params.has_key? :photo
      unless PhotoMetadata.where(id: params[:photo]).exists?
        render json:[{error:"Unable to find photo by id #{params[:photo]}"}], status: :not_acceptable
        return
      end
      @post.photo = params[:photo]
    end

    @post.save
    if @post.valid?
      render_json stream_post: @post.decorate.to_hash
    else
      render_json errors: @post.errors.full_messages
    end
  end

  def like
    @post = @post.add_like current_username
    render status: :ok, json: {status: 'ok', likes: @post.likes }
  end

  def show_likes
    render status: :ok, json: {status: 'ok', likes: @post.likes }
  end

  def unlike
    @post = @post.remove_like current_username
    render status: :ok, json: {status: 'ok', likes: @post.likes }
  end

  ## The following functions are helpers for the finding of new posts in the stream

  def want_newest_posts?
    not params.has_key?(:start)
  end

  def newest_posts
    start = DateTime.now.to_f * 1000
    params[:start] = start
    older_posts.merge!({next_page: start+1})
  end

  def want_older_posts?
    params.has_key?(:start) and params.has_key?(:older_posts)
  end

  def older_posts
    start_loc = params[:start]
    author = params[:author] || nil
    limit = params[:limit] || PAGE_LENGTH
    posts = StreamPost.at_or_before(start_loc, author).limit(limit).order_by(timestamp: :desc).map { |x| x }
    next_page = posts.last.nil? ? 0 : (posts.last.timestamp.to_f * 1000).to_i - 1
    {stream_posts: posts.map{|x| x.decorate.to_hash}, next_page: next_page}
  end

  def want_newer_posts?
    params.has_key?(:start) and not params.has_key?(:older_posts)
  end

  def newer_posts
    start_loc = params[:start]
    author = params[:author] || nil
    limit = params[:limit] || PAGE_LENGTH
    posts = StreamPost.at_or_after(start_loc, author).limit(limit).order_by(timestamp: :asc).map { |x| x }
    next_page = posts.last.nil? ? 0 : (posts.first.timestamp.to_f * 1000).to_i + 1
    {stream_posts: posts.map{|x| x.decorate.to_hash}, next_page: next_page}
  end
end