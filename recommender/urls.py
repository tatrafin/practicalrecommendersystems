from django.urls import path

from recommender import views

urlpatterns = [
    path('chart/', views.chart, name='chart'),
    path('association_rule/<str:content_id>/', views.get_association_rules_for, name='get_association_rules_for'),
    path('ar/<str:user_id>/', views.recs_using_association_rules, name='recs_using_association_rules'),
    path('sim/user/<str:user_id>/<str:sim_method>/', views.similar_users, name='similar_users'),
    path('cb/item/<str:content_id>/', views.similar_content, name='similar_content'),
    path('cb/user/<str:user_id>/', views.recs_cb, name='recs_cb'),
    path('cf/user/<str:user_id>/', views.recs_cf, name='recs_cb'),
    path('funk/user/<str:user_id>/', views.recs_funksvd, name='recs_funksvd'),
    path('fwls/user/<str:user_id>/', views.recs_fwls, name='recs_fwls'),
    path('bpr/user/<str:user_id>/', views.recs_bpr, name='recs_fwls'),
    path('pop/user/<str:user_id>/', views.recs_pop, name='recs_pop'),
]
