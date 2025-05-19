/**
* Name: raycasting
* Based on the internal empty template. 
* Author: baptiste
* Tags: 
*/


model raycasting



global {
	
	
	//player events
	string direction_asked <- "None" among:["None", "Left", "Right", "Front", "Back"];
	float asked_heading_delta;
	float angular_speed <- 100.0;
	
	image wall_txt 	<- image(image_file("../includes/wall2.png"));
	image enemy_txt	<- image(image_file("../includes/baddy.png"));
	image floor		<- image(image_file("../includes/floor2.png"));
	image sky		<- image(image_file("../includes/sky2.png"));
	image gun		<- image(image_file("../includes/gun2.png"));
	
	// game life cycle
	float last_frame_time;
	list<float> fps;
	
	// world dimensions
	geometry shape		<- rectangle(100, 100); // basically screen size, many things break when changing the dimensions
	int nb_cells_width	<- 20;
	int nb_cells_height <- 20;
	float cell_width 	<- world.shape.width/nb_cells_width;
	float cell_height	<- world.shape.height/nb_cells_height;
	
	// general helpers
	float epsilon <- 0.00001;// a small number to help with some calculations
		
	
	// constants for raycasting algorithm
	float FOV <- 90.0;
	float half_FOV <- FOV/2;
	int nb_rays <- 150;
	float step_angle <- FOV/nb_rays;
	
	
	// draw obstacles
	float wall_base_height <- world.shape.height;
	float wall_half_height <- wall_base_height/2;
	float wall_width	<- shape.width/nb_rays;
	int pxl_width 		<- int(wall_txt.width/nb_rays);
	int pxl_height 		<- wall_txt.height;
	int enemy_pxl_width 	<- int(enemy_txt.width/nb_rays);
	int enemy_pxl_height	<- enemy_txt.height;

	
	init {
		
		last_frame_time <- gama.machine_time#ms;
		create player;
		create baddy number:30;
//		do pre_slice_walls;
		
	}
	
	
//	action pre_slice_walls{
//		loop offset from:0 to:wall_txt.width-pxl_width-1{
//			let i <- getSlicedImage(offset, 1);
//		}
//	}
	
//	map<int, image> images <- [];
//	// Lazy initialisation of slices of images
//	image getSlicedImage(int offset, float ratio){
//		image cached <- images[offset];
//		if cached != nil {
//			return cached;
//		}
//		 cached <- wall_txt clipped_with (offset, 0, pxl_width, pxl_height)
// 					with_size (pxl_width, pxl_height* ratio) // we apply the proportions we need
// 					//TODO: it's correct for the first rendering but not after (shouldn't be too ugly with normal range of values
// 					// we need that for the moment as gama is unable to release the memory of images
//		 					;
//		images[offset] <- cached;
//		return cached;
//		
//	}

	reflex game_loop {
		float current <- gama.machine_time#ms;
		float delta <- current - last_frame_time + epsilon;// adding epsilon to cancel divisions by zero
		
		do game_loop(delta);
	
		last_frame_time <- current;
		fps <+ 1/delta;
		if length(fps) > 10 {
			remove from:fps index:0;
		}
	}
	
	
	
	action game_loop(float delta){
		// process movement
		ask player {
			heading <- heading - asked_heading_delta * delta;
			asked_heading_delta <- 0.0;
			do process_movement(delta);
			do update_rays;
			do update_image_lists;
		}
		
	}
	
	action arrow_up {
		direction_asked <- "Front";
	}
	action arrow_down {
		direction_asked <- "Back";
	}
	action arrow_left {
		direction_asked <- "Left";
	}
	action arrow_right {
		direction_asked <- "Right";
	}
	action rotate_right{
		asked_heading_delta <- -angular_speed;
	}
	action rotate_left{
		asked_heading_delta <- angular_speed;
	}
}


// The game map, describes the location of walls and enemies
grid game_map width:nb_cells_width height:nb_cells_height{

	string type <- "floor" among:["floor", "wall"];
	list<baddy> enemies <- [] update:baddy overlapping self;
	
	init {
		type <- rnd_choice(map(["floor"::0.8, "wall"::0.2]));
		if type = "wall" {
			color <- #brown;
		}
		else {
			color <- #grey;
		}
	}
	

}

species baddy skills:[moving] {
	
//	geometry shape <- rectangle(cell_width,cell_height);
	geometry shape <- rectangle(1,1);
	rgb color <- #red;
	
	init {
		loop while:(game_map overlapping (shape at_location location)) one_matches (each.type = "wall"){
			location <- any_location_in(world.shape);
		}
	}
}


species player {
	
	// movement 
	float speed <- 50#km/#h;
	float heading;
	geometry shape <- circle(1);
	
	// field of view
	list<geometry> rays <- list_with(nb_rays, nil); // for debug only
	map<int, list<float>> walls;
	map<int, list<float>> enemies;
	
	list<list> walls_to_draw <- list_with(nb_rays, [nil, 0, 0, 0]);
	list<list> enemies_to_draw;
	
	init {
		loop while:(game_map overlapping (shape at_location location)) one_matches (each.type = "wall"){
			location <- any_location_in(world.shape);
		}
	}
	
	float better_mod(float a, float base) {
		return a - floor(a/base) * base;
	}
	
	
	// fills the rays list with all the rays of the fov of the player
	action update_rays {
	
		let ox <- location.x;
		let oy <- location.y;
		let x_map <- int(location.x/cell_width)*cell_width;
		let y_map <- int(location.y/cell_height)*cell_height;
		
		walls <- [];
		enemies <- [];
		
		let ray_angle <- heading - half_FOV;
		loop ray from:0 to: nb_rays-1 {
			let sin_a <- sin(ray_angle);
			let cos_a <- cos(ray_angle);
			float depth_vert;
			float depth_hor;
			bool hor_enemy <- false;
			bool ver_enemy <- false;
			
			// ==========================================
			// looking for intersection on vertical lines
			// ==========================================
			
			// cos_a = 0 means we are looking straight downward/upwards so vertical line collision cannot happen	
			float x_vert;
			float y_vert;
			if cos_a != 0 {
				
				float dx;
				// if we are looking towards the right side, we start on the next vertical line
				if cos_a > 0 { 
					dx 		<- cell_width;
					x_vert 	<- x_map + dx;
				}
				// if we are looking towards the left side we increment in the opposite direction
				else {
					// minus epsilon so we are just a bit left of the vertical line to hit the wall on the left
					x_vert <- x_map - epsilon; 
					dx <- -cell_width;
				}
				
				depth_vert <- (x_vert - ox)/cos_a;
				y_vert <- oy + depth_vert * sin_a;
				
				float delta_depth <- dx/cos_a;
				float dy <- delta_depth * sin_a;
				
				loop i from:0 to:int(sqrt(nb_cells_width*nb_cells_width + nb_cells_height*nb_cells_height))-1 {
					int x <- int(int(x_vert)/cell_width);
	    			int y <- int(int(y_vert)/cell_height);
	    			
	    			// if we are out of map or touched a wall it's over
	    			if x < 0 or x >= nb_cells_width or y < 0 or y >= nb_cells_height{
	    				break;
	    			} 
	    			else {
	    				
	    				// first we look for enemy collisions
	    				float closest_enemy_x <- 0.0;
	    				float closest_enemy_y <- 0.0;
	    				float closest_enemy_dist <- world.shape.width;
    					//probably not enough
    					loop enemy over:game_map[x,y].enemies{
							// we consider the enemy as a plane perpendicular to the current ray
							// we need to compute the distance on the ray at which it intersects the plane
							let t <- -((location.x - enemy.location.x) * cos_a + (location.y - enemy.location.y) * sin_a);
							let x_on_ray <- location.x + t * cos_a;
							let y_on_ray <- location.y + t * sin_a;
							let distance <- enemy distance_to {x_on_ray, y_on_ray};
							// If the enemy is close enough to be drawn
							if distance <= enemy.shape.width/2{
		    					ver_enemy <- true;
		    					if distance < closest_enemy_dist {
		    						closest_enemy_x <- x_on_ray;
		    						closest_enemy_y <- y_on_ray;
		    					}
							}
    					}
    					if ver_enemy{
							x_vert <- closest_enemy_x;
							y_vert <- closest_enemy_y;
    						break;
    					}   					
	    					
	    				if game_map[x,y].type = "wall"{
			                break;
		            	}
		            }
					
					x_vert <- x_vert + dx;
					y_vert <- y_vert + dy;
				}
			}
			
			// ==========================================
			// looking for intersection on horizontal lines
			// ==========================================
			
			// sin_a = 0 means we are looking straight right/left so horizontal line collision cannot happen
			float x_hor;
			float y_hor;
			if sin_a != 0 {
				
				float dy;
				
				if sin_a > 0 { 
					// minus epsilon so we are just a bit above of the horizontal line to hit the wall on the top
					dy 		<- cell_height;
					y_hor 	<- y_map  + dy;
				}
				// if we are looking towards the bottom, we start on the next horizontal line
				else {
					dy <- -cell_height;
					y_hor <- y_map - epsilon; 
				}
				
				depth_hor <- (y_hor - oy)/sin_a;
				x_hor <- ox + depth_hor * cos_a;
				
				float delta_depth <- dy/sin_a;
				float dx <- delta_depth * cos_a;
				loop i from:0 to:int(sqrt(nb_cells_width*nb_cells_width + nb_cells_height*nb_cells_height))-1 {
					int x <- int(int(x_hor)/cell_width);
	    			int y <- int(int(y_hor)/cell_height);

	    			// if we are out of map or touched a wall it's over
	    			if x < 0 or x >= nb_cells_width or y < 0 or y >= nb_cells_height{
	    				break;
	    			} 
	    			else {

	    				
	    				float closest_enemy_x <- 0.0;
	    				float closest_enemy_y <- 0.0;
	    				float closest_enemy_dist <- world.shape.width;
	    				
	    				//probably not enough
    					loop enemy over:game_map[x,y].enemies{
							// we consider the enemy as a plane perpendicular to the current ray
							// we need to compute the distance on the ray at which it intersects the plane
							let t <- -((location.x - enemy.location.x) * cos_a + (location.y - enemy.location.y) * sin_a);
							let x_on_ray <- location.x + t * cos_a;
							let y_on_ray <- location.y + t * sin_a;
							let distance <- enemy distance_to {x_on_ray, y_on_ray};
							// If the enemy is close enough to be drawn
							if distance <= enemy.shape.width/2{
		    					hor_enemy <- true;
		    					if distance < closest_enemy_dist {
		    						closest_enemy_x <- x_on_ray;
		    						closest_enemy_y <- y_on_ray;
		    					}
							}
    					}
    					if hor_enemy{
							x_hor <- closest_enemy_x;
							y_hor <- closest_enemy_y;
    						break;
    					} 
	    				
	    				if game_map[x,y].type = "wall"{
			                break;
		            	}
		            }
					
					x_hor <- x_hor + dx;
					y_hor <- y_hor + dy;
				}
			}
			
			// we check which one of the vert or hor is the shortest 
			point hor 	<- {x_hor, y_hor};
			point vert	<- {x_vert, y_vert};
			point best;
			float offset;
			bool enemy <- false;
			if location distance_to hor < location distance_to vert {
				best <- hor;
				enemy <- hor_enemy;
				offset <- better_mod(x_hor, cell_width);
				if sin_a > 0 {
					offset <- cell_width - offset;
				}
				offset <- offset/cell_width; // we scale the offset 
			}
			else {
				best <- vert;
				enemy <- ver_enemy;
				offset <- better_mod(y_vert, cell_height);
				if cos_a <= 0 {
					offset <- cell_height - offset;
				}
				offset <- offset/cell_height; // we scale the offset 
			}
			rays[ray] <- line(location, best);
			let corrected_depth <- location distance_to best;
			// to counter fishbowl effect
			corrected_depth <- corrected_depth * cos(heading - ray_angle);
			// we register it differently if it's a wall or an enemy
			if not enemy {
				if ! (walls.keys contains ray) or (walls[ray][0] > corrected_depth) {
		    		walls[ray] <- [corrected_depth, offset];
				}
			}
			else {
				enemies[ray] <- [corrected_depth, offset];
			}
			
			ray_angle <- ray_angle + step_angle;
		}
	
	}
	
	action update_image_lists {
		
		float corrected_wall_half_height <- wall_half_height/tan(half_FOV);
		
		int i <- 0;
		list<list> walls_cp <- walls.keys collect list(each, walls[each][0], walls[each][1]);
		loop wall over:walls_cp {
			
			float x_start		<- float(wall[0]);
			float depth 		<- float(wall[1]);
			float half_height 	<- min(corrected_wall_half_height/(depth+epsilon), world.shape.height/2);
			float full_height 	<- half_height*2;
			int offset 			<- int(float(wall[2]) * (wall_txt.width - pxl_width));

			// cut the right section of the texture
			image wall_part <- wall_txt clipped_with (offset, 0, pxl_width, pxl_height);
			// store all the infos in the list
			walls_to_draw[i] <- [wall_part, x_start, half_height, depth];
			i <- i + 1;
		}
		
		enemies_to_draw <- [];
		list<list> enemies_cp <- enemies.keys collect list(each, enemies[each][0], enemies[each][1]);
		loop enemy over: enemies_cp {
			
			float x_start		<- float(enemy[0]);
			float depth 		<- float(enemy[1]);
			float half_height 	<- min(corrected_wall_half_height/(depth+epsilon), world.shape.height/2);
			float full_height 	<- half_height*2;
			int offset 			<- int(float(enemy[2]) * (enemy_txt.width - enemy_pxl_width));
			
			image enemy_part <- enemy_txt
								 clipped_with (offset, 0, enemy_pxl_width, enemy_pxl_height)
								;
			enemies_to_draw <+ [enemy_part, x_start, half_height, depth];
		}
	}
	
	
	action process_movement(float delta) {
		
		float dx <- 0.0;
		float dy <- 0.0;
		let adjusted_speed <- delta * speed;

		// processing the correct dx/dy in function of the direction asked			
		switch direction_asked {
			match "Front" {
				dx <- adjusted_speed * cos(heading);
				dy <- adjusted_speed * sin(heading);
			}
			match "Left" {
				dx <-  adjusted_speed * sin(heading);
				dy <- -adjusted_speed * cos(heading);	
			}
			match "Back" {
				dx <- -adjusted_speed * cos(heading);
				dy <- -adjusted_speed * sin(heading);
			}
			match "Right" {
				dx <- -adjusted_speed * sin(heading);
				dy <-  adjusted_speed * cos(heading);				
			}
		}
		
		let x <- location.x + dx;
		let y <- location.y + dy;
		//if we don't collide with a wall or get out of bound we move
		if 		x between(0, world.shape.width) 
			and y between(0, world.shape.height) 
			and game_map[int(x/cell_width), int(y/cell_height)].type != "wall" {
			location <- {x, y};
		}
		direction_asked <- "None";
	}
	
	
	aspect default {
		draw shape color:#blue;
		loop ray over:rays {
			draw ray color:#green;		
		}
		draw line(location, {location.x + 3 * cos(heading), location.y + 3 * sin(heading)}) color:#yellow width:3;
	}
	
	// darkens objects farther away
	float max_vision <- 15#m;
	rgb darkens(rgb init_color, float distance){
		list<float> c <- list<float>(to_hsb(init_color));
		c[2] <- max(c[2], exp(-distance/max_vision));
		return hsb(c[0],c[1],c[2]);
	}
	

	
	aspect eye_of_the_beholder {
		
		loop wall over:copy(walls_to_draw) {
			
			image wall_part		<- image(wall[0]);
			float x_start		<- float(wall[1]);
			float half_height 	<- float(wall[2]);
			float depth 		<- float(wall[3]);
			float full_height 	<- half_height*2;
			
			// we draw the wall
			draw wall_part at:{x_start* wall_width + wall_width/2, world.shape.height/2-half_height/2, exp(-depth)} 
							size:{wall_width, full_height}
							;
		}
		
		loop enemy over: copy(enemies_to_draw) {
			
			image enemy_part	<- image(enemy[0]);
			float x_start		<- float(enemy[1]);
			float half_height 	<- float(enemy[2]);
			float depth 		<- float(enemy[3]);
			float full_height 	<- half_height*2;
			
			draw enemy_part at:{x_start* wall_width + wall_width/2, world.shape.height/2-half_height/2, exp(-depth)} 
							size:{wall_width, full_height}
							;
		}
	}
}

experiment play autorun:true{
	
	// We try to get 60 fps
	float minimum_cycle_duration <- 1.0/60.0;
	action up{
		write "up";
		ask simulation {do arrow_up;}
	}
	action down{
		ask simulation {do arrow_down;}
	}
	action left{
		ask simulation {do arrow_left;}
	}
	action right{
		ask simulation {do arrow_right;}
	}
	action rotate_right {
		ask simulation {do rotate_right;}
	}
	action rotate_left {
		ask simulation {do rotate_left;}
	}

//	reflex sync {
//		do update_outputs(true);
//	}
	
	output synchronized:true{
//	layout horizontal([0::50, 1::50]) navigator:false editors:false parameters:false consoles:true tray:true;
//		display logic type:3d toolbar:false antialias:false{
//			grid game_map border:#black;
//			species player;
//			species baddy;
//			event #arrow_up 	action:up;
//			event #arrow_down 	action:down;
//			event #arrow_left 	action:left;
//			event #arrow_right 	action:right;
//			//event mouse_move 	action:mouse_move;{ask simulation {do mouse_move;}}
////			event #mouse_down	action:mouse_down;
////			event #mouse_enter	action:mouse_enter;
////			event #mouse_exit	action:mouse_exit;
//		}
		
//		layout navigator:false editors:false parameters:false consoles:false tray:true;
		display rendering type:3d axes:false  toolbar:true antialias:false{
//			camera 'default' location: {50.0,50.0022,127.6281} target: {50.0,50.0,0.0} locked:true;			
//			camera 'my_camera' location: #from_above locked: true;
			graphics background {
				// draw floor
				//draw rectangle(world.shape.width, world.shape.height/2) at:{0, world.shape.height/2}+{world.shape.width/2,world.shape.height/4} color:#green;
				draw floor 	at:{0, world.shape.height/2}+{world.shape.width/2,world.shape.height/4} 
							size:{world.shape.width, world.shape.height/2}
							;
							
				// draw ceiling
//				draw rectangle(world.shape.width, world.shape.height/2) at:{0, world.shape.height/2}-{-world.shape.width/2,world.shape.height/4} color:#blue;
				draw sky 	at:{0, world.shape.height/2}-{-world.shape.width/2,world.shape.height/4} 
							size:{world.shape.width, world.shape.height/2}
							;
			
			}
			
			species player aspect:eye_of_the_beholder;	
			
			
			graphics gun_layer {
				draw gun 	at:{world.shape.width*0.75, world.shape.height*0.75}
							size:{world.shape.width/2, world.shape.height/2}
							;
			}
			
			graphics g{	
				draw "fps: " + mean(fps) with_precision 1 at:{0,-1} color:#red font:font("helvetica",14, #bold);					
			}
			
			event #arrow_up 	action:up;
			event #arrow_down 	action:down;
			event #arrow_left 	action:left;
			event #arrow_right 	action:right;
			event 'e'			action:rotate_right;
			event 'q'			action:rotate_left;
//			//event mouse_move 	action:mouse_move;{ask simulation {do mouse_move;}}
//			event #mouse_down	action:mouse_down;
//			event #mouse_enter	action:mouse_enter;
//			event #mouse_exit	action:mouse_exit;
			
		}
	}
//	
//	
//	reflex debug {
//		do compact_memory();
//	}
	
}