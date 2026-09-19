module Api
  module V1
    class NewsCommentController < ApiController
      before_action :check_basic_auth, only: [:create, :reply, :react, :reactors]

      def create
        parent_news = NewsFeed.find(params['parent_newsfeed_id'])

        comment = current_user.news_comments.create(text: params['text'], user_info: user_params_info, news_feed_id: params[:parent_newsfeed_id].to_i)

        if comment.valid?
          render json: NewsCommentBlueprint.render(comment), status: :ok
        else
          render json: :nothing, status: :unprocessable_entity
        end

      end

      # Responder a un comentario puntual (:id = comentario original). Solo
      # 1 nivel de anidamiento -- responder a una respuesta da 422 (mismo
      # criterio que auto-reaccionar en #react: el controller evita el caso
      # comun de antemano, NewsComment#parent_comment_must_be_top_level es
      # la red de seguridad real).
      def reply
        parent_comment = NewsComment.find(params[:id])

        if parent_comment.parent_comment_id.present?
          return render json: {}, status: :unprocessable_entity
        end

        comment = current_user.news_comments.create(
          text: params[:text],
          user_info: user_params_info,
          news_feed_id: parent_comment.news_feed_id,
          parent_comment_id: parent_comment.id,
        )

        if comment.valid?
          render json: NewsCommentBlueprint.render(comment), status: :ok
        else
          render json: :nothing, status: :unprocessable_entity
        end

        rescue ActiveRecord::RecordNotFound
          render json: {}, status: :not_found
      end

      def delete
        comment = NewsComment.find_by(id: params[:id])

        if comment&.destroy
          render json: {message: 'Delete Comment Success'}, status: :ok
        else
          render json: :nothing, status: :unprocessable_entity
        end
      end

      # Reaccion "Concordo"/"De acuerdo" a un comentario -- click = crea
      # (reacciona), segundo click sobre el mismo comentario = borra
      # (saca la reaccion). A diferencia de NewsFeedController#react no hay
      # un valor booleano que comparar: la presencia de la fila ES el
      # estado, asi que alcanza con buscar y togglear.
      def react
        comment = NewsComment.find(params[:id])
        reaction = NewsCommentReaction.find_by(user: current_user, news_comment: comment)

        if reaction.present?
          reaction.destroy!
          my_reaction = false
        else
          NewsCommentReaction.create!(user: current_user, news_comment: comment, user_info: reactor_info)
          my_reaction = true
        end

        render json: {
          myReaction: my_reaction,
          reactionCount: comment.news_comment_reactions.count,
        }, status: :ok

        rescue ActiveRecord::RecordNotFound
          render json: {}, status: :not_found
        rescue ActiveRecord::RecordInvalid
          render json: {}, status: :unprocessable_entity
      end

      # Lista de quien reacciono -- solo nombre/especialidad/pais (mismo
      # subset ya expuesto para autores de comentarios), nunca email ni
      # otro dato privado. Se pide solo al hacer click en el contador (ver
      # frontend), no viene con la carga inicial del feed.
      def reactors
        comment = NewsComment.find(params[:id])
        reactions = comment.news_comment_reactions.order(created_at: :asc).limit(50)

        render json: reactions.map { |r| (r.user_info || {}).except('email') }, status: :ok

        rescue ActiveRecord::RecordNotFound
          render json: {}, status: :not_found
      end

      private

      # Mismos campos que user_params_info (ApiController), pero sin el
      # guard de "params[:text].present?" -- ese guard esta pensado para
      # la creacion de un comentario/post (que siempre trae texto) y una
      # reaccion no tiene texto, asi que reusar user_params_info tal cual
      # siempre devolveria {}.
      def reactor_info
        {
          email: params[:email],
          complete_name: params[:complete_name],
          country: params[:country],
          city: params[:city],
          specialty: params[:specialty],
        }
      end
    end
  end
end
