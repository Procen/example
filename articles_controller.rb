class ArticlesController < ApplicationController
  before_action :article_categories_info, only: [:index, :show]
  skip_before_action :verify_authenticity_token, only: :download_image

  # before_action :authenticate_user!, only: [:new, :create, :update]

  def index
    @articles =
      if params[:category_id] == 'uncategories'
        Article.uncategorised.desc(:created_at)
      elsif params[:category_id]
        cat = ArticleCategory.find(params[:category_id])
        @articles = cat.articles
      else
        Article.desc(:created_at)
      end

    @articles = get_articles(@articles).page(params[:page]).per(4)
    @comments = Comment.where(commentable_type: 'Article').order(created_at: :desc).limit(3)
    render stream: true
  end

  def new
    @article = Article.new
    @statuses = Article.status.options
    @categories = ArticleCategory.all.pluck(:name, :id)
  end

  def create
    @article = Article.new(article_params)
    @article.content = @article.content.gsub('../', '/')
    if @article.save
      ArticleMailer.new_article(current_user.full_name, @article.id.to_s).deliver_later
      save_documents params[:documents] if params[:documents]
      redirect_to articles_path
    else
      redirect_to :back
    end
  end

  def download_image
    image    = Image.create params.permit(:file, :alt, :hint)
    render json: { location: image.file.url }
  end

  def show
    @article = Article.find(params[:id])
    @new_comment    = Comment.new
    @comments       = @article.comments.roots.page(params[:page]).per(5)
    @last_comments  = @comments.last_comments(3)
    @comments_count = @article.comments.count
  end

  def edit
    @article = Article.find(params[:id])
    redirect_to :back if current_user.pm? && @article.is_approved
    @tags = @article.tags.pluck(:name).join(',')
    @statuses = Article.status.options
    @categories = ArticleCategory.all.collect { |cat| [cat.name, cat.id] }
  end

  def update
    @article = Article.find(params[:id])
    @article.image.destroy if params[:remove_image].eql?('true') && params[:article][:image].blank?
    if @article.update(article_params)
      save_documents params[:documents] if params[:documents]
      redirect_to articles_path
    else
      redirect_to :back
    end

  end

  def destroy
    article = Article.find(params[:id])
    if article.destroy
      redirect_to articles_path
    else
      redirect_to articles_path
    end
  end
  def delete_document
    document = Document.find(params[:id])
    if document.destroy
      render json: { success: true }
    end
  end

  def approve_article
    article = Article.find(params[:id])
    if article.update(is_approved: !article.is_approved)
      ArticleMailer.article_approved(article.id.to_s).deliver_later if article.is_approved
      render json: { success: true, approved: article.is_approved, article_id: article.id.to_s }
    else
      render json: { error: article.errors }
    end
  end

  private

  def save_documents(documents)
    documents.each do |document|
      @article.documents.create(file: document)
    end
  end

  def article_categories_info
    @articles_size = Article.count
    @articles_uncategorised_size = Article.uncategorised.count
    @categories = ArticleCategory.includes(:articles).all
    # @group_article_categories = ArticleCategoriesArticle.group(:article_category_id).count
  end

  def article_params
    params.require(:article).permit(
      :title, :content, :user_id, :is_published, :publish_date, :article_tags, :status, :image,
      article_category_ids: []
    )
  end

  def get_articles(articles)
    if current_user.admin?
      articles
    elsif current_user.pm? || current_user.coach?
      articles.any_of({ is_approved: true }, { user_id: current_user.id })
    else
      articles.publish.published_date.approved
    end
  end

end
