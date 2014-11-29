require 'digest'
require 'RMagick'
require 'singleton'

class PhotoStore
  include Singleton

  # @return [Magick::ImageList]
  def read_image(temp_file, check_if_existing = false)
    temp_file = UploadFile.new(temp_file) unless temp_file.is_a? UploadFile
    return { status: 'File was not an allowed image type - only jpg, gif, and png accepted.' } unless temp_file.photo_type?
    if check_if_existing
      existing_photo = PhotoMetadata.where(md5_hash: temp_file.md5_hash).first
      return { status: 'File has already been uploaded.', photo: existing_photo.id.to_s } unless existing_photo.nil?
    end
    begin
      img_list = Magick::ImageList.new(temp_file.tempfile.path)
      puts "Image list size: #{img_list.size}, #{img_list.length}"
    rescue Java::JavaLang::NullPointerException
      # yeah, ImageMagick throws a NPE if the photo isn't a photo
      return { status: 'Photo could not be opened - is it an image?' }
    end
    if temp_file.extension == 'jpg' || temp_file.extension == 'jpeg'
      exif = EXIFR::JPEG.new(temp_file.tempfile)
      orientation = exif.orientation
      if orientation
        img_list = orientation.transform_rmagick(img_list)
      end
    end
    img_list
  end

  # @param [Magick::Image] img
  # @return [Magick::Image]
  def self.overlay_play_icon(img)
    play_overlay = Magick::Image::read('public/img/play_overlay.png').first
    puts "Playoverlay class #{play_overlay._image.class}"
    img.composite(play_overlay, Magick::NorthEastGravity, 0, 0, Magick::OverCompositeOp).flatten_images
  end

  def upload(temp_file, uploader)
    temp_file = UploadFile.new(temp_file)
    img_list = read_image temp_file, false
    return img_list if img_list.is_a? Hash
    img = img_list.first
    is_animated = (img_list.length > 1) || true
    puts "Detected animated gif: #{is_animated}"
    img = PhotoStore.overlay_play_icon(img) if is_animated
    photo = store(temp_file, uploader)
    img.resize_to_fit(200, 200).write "tmp/#{photo.store_filename}"
    FileUtils.move "tmp/#{photo.store_filename}", sm_thumb_path(photo.store_filename)
    puts "SMALL THUMB PATH: #{sm_thumb_path photo.store_filename}"
    img.resize_to_fit(800, 800).write "tmp/#{photo.store_filename}"
    FileUtils.move "tmp/#{photo.store_filename}", md_thumb_path(photo.store_filename)
    photo.save
    { status: 'ok', photo: photo.id.to_s }
  rescue EXIFR::MalformedJPEG
    { status: 'Photo extension is jpg but could not be opened as jpeg.' }
  end

  def store(file, uploader)
    new_filename = SecureRandom.uuid.to_s + Pathname.new(file.filename).extname.downcase
    photo = PhotoMetadata.new uploader: uploader,
                              original_filename: file.filename,
                              store_filename: new_filename,
                              upload_time: Time.now,
                              md5_hash: file.md5_hash
    FileUtils.copy file.tempfile, photo_path(photo.store_filename)
    photo
  end

  def initialize
    @root = Pathname.new(Rails.configuration.photo_store)

    @full = @root + 'full'
    @thumb = @root + 'thumb'
    @profiles = @root + 'profiles/'
    @profiles_small = @profiles + 'small'
    @full.mkdir unless @full.exist?
    @thumb.mkdir unless @thumb.exist?
    @profiles.mkdir unless @profiles.exist?
    @profiles_small.mkdir unless @profiles_small.exist?
  end

  def photo_path(filename)
    (build_directory(@full, filename) + filename).to_s
  end

  def sm_thumb_path(filename)
    (build_directory(@thumb, filename) + ('sm_' + filename)).to_s
  end

  def md_thumb_path(filename)
    (build_directory(@thumb, filename) + ('md_' + filename)).to_s
  end

  def small_profile_path(store_filename)
    (build_directory(@profiles_small, store_filename) + (store_filename)).to_s
  end

  def small_profile_img(store_filename)
    begin
      return Magick::Image::read(small_profile_path(store_filename)).first
    rescue Java::JavaLang::NullPointerException
      # yeah, ImageMagick throws a NPE if the photo isn't a photo
      return { status: 'Photo could not be opened - is it an image?' }
    end
  end

  @@mutex = Mutex.new

  def build_directory(root_path, filename)
    @@mutex.synchronize do
      first = root_path + filename[0]
      first.mkdir unless first.exist?
      second = first + filename[1]
      second.mkdir unless second.exist?
      second
    end
  end

  class UploadFile
    PHOTO_EXTENSIONS = %w(jpg jpeg gif png).freeze

    def initialize(file)
      @file = file
    end

    def extension
      @ext ||= Pathname.new(@file.original_filename).extname[1..-1].downcase
    end

    def photo_type?
      return true if PHOTO_EXTENSIONS.include?(extension)
      false
    end

    def tempfile
      @file.tempfile
    end

    def md5_hash
      @hash ||= Digest::MD5.file(@file.tempfile).hexdigest
    end

    def filename
      @file.original_filename
    end
  end

end