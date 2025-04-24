# frozen_string_literal: true

class ProductReviewsController < ApplicationController
  include Pagy::Backend

  PER_PAGE = 10

  before_action :fetch_product, only: [:set]

  def index
    product = Link.find_by_external_id(permitted_params[:product_id])
    return head :not_found unless product.present?
    return head :forbidden unless product.display_product_reviews || current_seller == product.user

    pagination, reviews = pagy(
      product.product_reviews
        .alive
        .visible_on_product_page
        .includes(:response, approved_video: :video_file, purchase: :purchaser)
        .order(rating: :desc, created_at: :desc, id: :desc),
      page: [permitted_params[:page].to_i, 1].max,
      limit: PER_PAGE
    )

    render json: {
      pagination: PagyPresenter.new(pagination).props,
      reviews: reviews.map { ProductReviewPresenter.new(_1).product_review_props }
    }
  end

  def show
    review = ProductReview
      .alive
      .visible_on_product_page
      .includes(:response, purchase: :purchaser, link: :user)
      .find_by_external_id!(permitted_params[:id])

    product = review.link
    return head :forbidden unless product.display_product_reviews || current_seller == product.user

    render json: {
      review: ProductReviewPresenter.new(review).product_review_props
    }
  end

  def set
    post_review
  end

  private
    def post_review
      purchase = @product.sales.find_by_external_id!(params[:purchase_id])

      if !ActiveSupport::SecurityUtils.secure_compare(purchase.email_digest, params[:purchase_email_digest].to_s)
        render json: { success: false, message: "Sorry, you are not authorized to review this product." }
        return
      end

      if purchase.created_at < 1.year.ago && @product.user.disable_reviews_after_year?
        render json: { success: false, message: "Sorry, something went wrong." }
        return
      end

      review = purchase.post_review(
        rating: set_params[:rating].to_i,
        message: set_params[:message],
        video_options: set_params[:video_options] || {}
      )

      render json: {
        success: true,
        review: ProductReviewPresenter.new(review.reload).review_form_props
      }
    rescue ActiveRecord::RecordInvalid => e
      render json: { success: false, message: e.message }
    rescue StandardError
      render json: { success: false, message: "Sorry, something went wrong." }
    end

    def permitted_params
      params.permit(:product_id, :page, :id)
    end

    def set_params
      params.permit(
        :rating, :message,
        video_options: [
          { destroy: [:id] },
          { create: [:url, :thumbnail_signed_id] }
        ]
      )
    end
end
